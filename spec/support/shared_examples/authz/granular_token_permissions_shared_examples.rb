# frozen_string_literal: true

RSpec.shared_examples 'authorizing granular token permissions' do |permissions, expected_success_status: :success,
    context_type: :rest, legacy_token_scopes: nil|
  granular_permissions = Array(permissions)
  individual_permission_labels = granular_permissions.map do |permission|
    assignable = Authz::PermissionGroups::Assignable.preferred_for_permission(permission)
    "#{assignable.resource_name}: #{assignable.action.titleize}"
  end.uniq.sort

  let(:is_graphql) { context_type == :graphql }

  let(:boundary) { ::Authz::Boundary.for(boundary_object) }

  let(:error_boundary_object) { boundary_object }
  let(:acceptable_messages) { [message] }

  shared_examples 'granting access' do
    it 'grants access', :aggregate_failures do
      request

      expect(response).to have_gitlab_http_status(expected_success_status)

      if is_graphql
        expect_graphql_errors_to_be_empty
        expect(graphql_data).to be_present
        expect(graphql_data.values).to all(be_present)

        expect_graphql_mutation_errors_to_be_empty if respond_to?(:mutation)
      end
    end
  end

  shared_examples 'denying access' do
    it 'denies access', :aggregate_failures do
      request

      if is_graphql
        expect(response).to have_gitlab_http_status(:success)

        # queries return nil values when unauthorized, mutations raise an error
        if respond_to?(:mutation)
          expect(graphql_errors).to include(
            a_hash_including('message' => satisfy { |m| acceptable_messages.any? { |e| m.include?(e) } })
          )
        else
          expect(graphql_data.values).to all(
            satisfy { |value| value.nil? || value['nodes'] == [] }
          )
        end
      else
        expect(response).to have_gitlab_http_status(:forbidden)

        # Only check JSON body if present (GET/POST/etc have bodies, HEAD doesn't)
        if response.body.present?
          expect(json_response['error']).to eq('insufficient_granular_scope')
          expect(json_response['error_description']).to include(message)
        end
      end
    end
  end

  context 'when authenticating with a legacy personal access token' do
    let(:pat) { create(:personal_access_token, :admin_mode, user: user, scopes: legacy_token_scopes || %w[api]) }
    let(:root_ancestor) { boundary.namespace&.root_ancestor }

    it_behaves_like 'granting access'

    context 'when namespace enforces granular tokens' do
      let(:message) { 'Access denied: This operation requires a fine-grained personal access token' }

      before do
        skip 'namespace has no top-level group' unless root_ancestor&.group_namespace?
        skip 'enforcement does not apply to bot tokens' unless user.human?

        stub_feature_flags(granular_personal_access_tokens_enforcement_saas: root_ancestor)

        ::NamespaceSetting.find_by!(namespace_id: root_ancestor.id).update!(
          enforce_granular_tokens: true,
          granular_tokens_enforced_after: Date.current
        )
      end

      it_behaves_like 'denying access'
    end
  end

  context 'when authenticating with a granular personal access token' do
    let(:assignables) do
      granular_permissions.map do |permission|
        ::Authz::PermissionGroups::Assignable.preferred_for_permission(permission).name
      end.uniq
    end

    let(:pat) { create(:granular_pat, user: user, boundary: boundary, permissions: assignables) }

    it_behaves_like 'granting access'

    context 'when the `granular_personal_access_tokens` feature flag is disabled' do
      before do
        stub_feature_flags(granular_personal_access_tokens: false)
      end

      let(:message) { 'Access denied: Fine-grained personal access tokens are not yet supported.' }

      it_behaves_like 'denying access'
    end

    context 'when an authorizing granular scope is missing' do
      before do
        pat.granular_scopes.delete_all

        # Disable the public-access bypass so the "denying access" assertion
        # exercises the missing-scope path. Without this stub the bypass
        # consults `policy_for(nil, ...)` and grants access on public resources,
        # masking the denial we want to verify.
        null_policy = instance_double(::DeclarativePolicy::Base, allowed?: false)
        allow(::DeclarativePolicy).to receive(:policy_for).and_call_original
        allow(::DeclarativePolicy).to receive(:policy_for)
          .with(nil, anything, hash_including(:cache)).and_return(null_policy)
      end

      let(:acceptable_messages) do
        boundary_type_label = ::Authz::Boundary.for(error_boundary_object).type_label
        prefix = "Access denied: This operation requires a fine-grained personal access token " \
          "with the following #{boundary_type_label} permissions:"
        (individual_permission_labels + [individual_permission_labels.join(', ')]).uniq
          .map { |label| "#{prefix} [#{label}]." }
      end

      let(:message) { acceptable_messages.last }

      it_behaves_like 'denying access'
    end

    # A granular PAT without a matching scope reaches a public resource only through the
    # public-access bypass, which serves the request as anonymous. A read must return what an
    # anonymous request returns, also when the token's user is a member who could read more.
    # A write must be denied; the scopeless token is rejected before the endpoint runs.
    context 'when the token holds no scope for a public resource' do
      it 'serves the same response as an anonymous request' do
        unless boundary_object.is_a?(::Project) || boundary_object.is_a?(::Group)
          skip 'only meaningful on Project/Group boundaries'
        end

        skip 'public-access bypass only applies to public resources' unless boundary_object.public?

        [create(:user), user].each do |token_user|
          outcome = request_outcome_as(create(:granular_pat, user: token_user))

          if write_request?
            expect(outcome[:success]).to be(false)
          else
            anonymous_outcome = request_outcome_as(nil)
            skip 'the request cannot be sent without a token' if anonymous_outcome.nil?
            skip 'the request authenticates without the token' if request_sent_credentials?

            if is_graphql
              # The public access rule only admits permissions that are policy abilities (not
              # read_job, for example), so GraphQL can hide nested types the anonymous request sees.
              expect(outcome[:data]).to satisfy("expose nothing beyond #{anonymous_outcome[:data]}") { |data|
                graphql_data_within?(data, anonymous_outcome[:data])
              }
            else
              expect(outcome).to eq(anonymous_outcome)
            end
          end
        end
      end
    end
  end

  def write_request?
    is_graphql ? respond_to?(:mutation) : !(response.request.get? || response.request.head?)
  end

  def request_sent_credentials?
    sent = response.request

    %w[private_token access_token job_token].any? { |param| sent.query_parameters.key?(param) } ||
      %w[PRIVATE-TOKEN Authorization JOB-TOKEN].any? { |header| sent.headers[header].present? }
  end

  def graphql_data_within?(data, anonymous_data)
    case data
    when nil
      true
    when Hash
      anonymous_data.is_a?(Hash) && data.all? { |key, value| graphql_data_within?(value, anonymous_data[key]) }
    when Array
      anonymous_data.is_a?(Array) && data.all? { |item| anonymous_data.any? { |alt| graphql_data_within?(item, alt) } }
    else
      data == anonymous_data
    end
  end

  def request_outcome_as(new_pat)
    return unless dispatch_request_as(new_pat)

    if is_graphql
      { success: graphql_errors.blank?, data: graphql_data }
    else
      { success: response.successful?, body: (response.body if response.successful?) }
    end
  end

  # Re-dispatches the caller-defined `let(:request)` with a different `pat`.
  # Stubs `pat` and invalidates the let memoization so `request` re-evaluates.
  #
  # Implementation notes:
  # - We reach into `__memoized` because RSpec offers no public API for
  #   per-key memoization invalidation. Verified against rspec-core 3.13;
  #   if its internal storage layout changes this is the line to update.
  # - The rescue is scoped to NoMethodError on a nil-stubbed pat: some
  #   callers reference `pat.token` directly (e.g. basic auth headers).
  #   We don't short-circuit `nil` because callers that pass `pat` to
  #   helpers which gracefully accept a nil token should still dispatch:
  #   that path actually exercises anonymous HTTP and surfaces drift
  #   between policy-based bypass and HTTP-level authz.
  def dispatch_request_as(new_pat)
    allow(self).to receive(:pat).and_return(new_pat)
    __memoized.instance_variable_get(:@memoized).delete(:request)

    request
    true
  rescue NoMethodError
    raise unless new_pat.nil?

    false
  end
end

RSpec.shared_examples 'authorizing granular token permissions for GraphQL' do |permissions|
  # `include_examples` (not `it_behaves_like`) so the inner example group's
  # default `let` definitions (e.g. `error_boundary_object`) land on this
  # group and remain overridable from the caller's customization block.
  include_examples 'authorizing granular token permissions', permissions, context_type: :graphql
end

RSpec.shared_examples 'authorizing granular token permissions for GraphQL with a skipped child type' do |permissions|
  context 'when a granular token authorizes the parent type' do
    let(:assignables) do
      Array(permissions).map do |permission|
        ::Authz::PermissionGroups::Assignable.for_permission(permission).min_by(&:name).name
      end.uniq
    end

    let(:pat) do
      create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(boundary_object), permissions: assignables)
    end

    it 'returns the data of the type that skips granular token authorization', :aggregate_failures do
      request

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(*skipped_data_path)).to be_present
    end
  end

  context 'when a granular token does not authorize the parent type' do
    let(:pat) { create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(boundary_object)) }

    it 'does not return the data of the type that skips granular token authorization', :aggregate_failures do
      request

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(*skipped_data_path)).to be_nil
    end
  end
end

RSpec.shared_examples 'denying a granular token that only authorizes the parent of a field' do |parent_permissions|
  let(:pat) do
    assignables = Array(parent_permissions).map do |permission|
      ::Authz::PermissionGroups::Assignable.for_permission(permission).min_by(&:name).name
    end.uniq

    create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(boundary_object), permissions: assignables)
  end

  it 'returns the parent without the field', :aggregate_failures do
    request

    expect(graphql_errors).to be_nil
    expect(graphql_data_at(*parent_data_path)).to be_present
    expect(graphql_data_at(*field_data_path)).to satisfy { |value| value.nil? || value['nodes'] == [] }
  end
end
