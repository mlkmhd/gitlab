# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::LookupRoleAssignmentsService, feature_category: :artifact_registry do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:user, organization: organization) }

  let(:resource_id) { Gitlab::Utils.uuid_v7 }
  let(:resource_ids) { [resource_id] }
  let(:roles) { [] }
  let(:page_size) { nil }
  let(:page_after) { nil }
  let(:token) { 'ar-token' }

  let(:client) { instance_double(Authn::IamService::LookupRelationshipsClient) }
  let(:ar_client) { instance_double(ArtifactRegistry::Client) }
  let(:lookup_response) do
    ::Gitlab::Iam::Lookup::V1::LookupRelationshipsResponse.new(
      relationships: [
        ::Gitlab::Iam::Relationships::V1::Relationship.new(
          object: ::Gitlab::Iam::Relationships::V1::Object.new(id: resource_id)
        )
      ],
      next_page_token: 'next-page'
    )
  end

  before do
    issuer = instance_double(Authn::TokenExchange::TokenIssuer, token: token)
    allow(Authn::TokenExchange::TokenIssuer).to receive(:new).and_return(issuer)

    allow(Authn::IamService::LookupRelationshipsClient).to receive(:new).and_return(client)
    allow(client).to receive(:lookup).and_return(lookup_response)

    allow(ArtifactRegistry::Client).to receive(:new).and_return(ar_client)
    allow(ar_client).to receive(:verify_repositories).and_return([])
  end

  subject(:execute) do
    described_class.new(
      current_user: current_user,
      organization: organization,
      resource_ids: resource_ids,
      roles: roles,
      page_size: page_size,
      page_after: page_after
    ).execute
  end

  def iam_error(reason)
    Authn::IamService::LookupRelationshipsClient::RequestError.new('diagnostic', reason: reason)
  end

  def lookup_objects
    captured = nil
    expect(client).to receive(:lookup) do |objects:, **_kwargs|
      captured = objects
      lookup_response
    end

    expect(execute).to be_success
    captured
  end

  context 'when the query is valid' do
    it 'reads through IAM and returns the relationships and next page token', :aggregate_failures do
      result = execute

      expect(result).to be_success
      expect(result.payload[:role_assignments].map { |r| r.object.id }).to eq([resource_id])
      expect(result.payload[:next_page_token]).to eq('next-page')
    end

    it 'passes the scoped objects, filters, pagination, and token to the client', :aggregate_failures do
      expect(client).to receive(:lookup) do |objects:, kinds:, role_ids:, page_size:, page_token:, token:|
        expect(objects).to match_array([{ id: resource_id, ancestor_ids: [] }])
        expect(kinds).to eq([:KIND_ASSIGNMENT])
        expect(role_ids).to eq([])
        expect(page_size).to be_nil
        expect(page_token).to be_nil
        expect(token).to eq('ar-token')

        lookup_response
      end

      expect(execute).to be_success
    end

    # IAM only accepts canonical lowercase ids, so the service normalizes case
    # instead of rejecting an uppercase id.
    context 'with uppercase resource ids' do
      let(:resource_ids) { [resource_id.upcase] }

      it 'downcases the ids before passing them to the client' do
        expect(lookup_objects).to match_array([{ id: resource_id, ancestor_ids: [] }])
      end
    end

    context 'with a role filter' do
      let(:roles) { [:artifact_admin] }

      it 'maps role names to role ids for the client' do
        expect(client).to receive(:lookup)
          .with(hash_including(role_ids: [ArtifactRegistry::Roles.uuid_for(:artifact_admin)]))
          .and_return(lookup_response)

        expect(execute).to be_success
      end
    end

    context 'with a platform role filter' do
      let(:roles) { [:organization_admin] }

      it 'maps the role name to its glaz-roles id for the client' do
        expect(client).to receive(:lookup)
          .with(hash_including(role_ids: [Authz::Organizations::Roles.organization_admin_uuid]))
          .and_return(lookup_response)

        expect(execute).to be_success
      end
    end

    context 'for any query' do
      it 'always scopes the read to the assignment kind' do
        expect(client).to receive(:lookup)
          .with(hash_including(kinds: [:KIND_ASSIGNMENT]))
          .and_return(lookup_response)

        expect(execute).to be_success
      end
    end

    context 'with no resource ids' do
      let(:resource_ids) { [] }

      it 'reads the whole organization (IAM enforces the owner requirement)' do
        expect(client).to receive(:lookup)
          .with(hash_including(objects: []))
          .and_return(lookup_response)

        expect(execute).to be_success
      end
    end

    describe 'page size clamping' do
      context 'when the requested size exceeds the cap' do
        let(:page_size) { 5000 }

        it 'clamps to MAX_PAGE_SIZE' do
          expect(client).to receive(:lookup)
            .with(hash_including(page_size: described_class::MAX_PAGE_SIZE))
            .and_return(lookup_response)

          expect(execute).to be_success
        end
      end

      context 'when the requested size is within the cap' do
        let(:page_size) { 50 }

        it 'passes it through' do
          expect(client).to receive(:lookup)
            .with(hash_including(page_size: 50))
            .and_return(lookup_response)

          expect(execute).to be_success
        end
      end

      context 'when the requested size is not positive' do
        let(:page_size) { 0 }

        it 'falls back to the server default (nil)' do
          expect(client).to receive(:lookup)
            .with(hash_including(page_size: nil))
            .and_return(lookup_response)

          expect(execute).to be_success
        end
      end
    end

    context 'when paging with a page token' do
      let(:page_after) { 'opaque-cursor' }

      it 'forwards it as the client page token' do
        expect(client).to receive(:lookup)
          .with(hash_including(page_token: 'opaque-cursor'))
          .and_return(lookup_response)

        expect(execute).to be_success
      end
    end
  end

  # Its own organization, because the rest of this file runs with no mapping and
  # inverse_of on NamespaceMapping#organization writes a new mapping into the
  # shared organization's cached has_one.
  describe 'the ancestor named on each resource' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:namespace_mapping) { create(:artifact_registry_namespace_mapping, organization: organization) }
    let_it_be(:current_user) { create(:user, organization: organization) }

    let(:namespace_id) { namespace_mapping.ar_namespace_id }
    let(:other_resource_id) { Gitlab::Utils.uuid_v7 }

    it 'names the namespace for a verified repository, so a namespace admin is admitted' do
      expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

      expect(lookup_objects).to contain_exactly({ id: resource_id, ancestor_ids: [namespace_id] })
    end

    context 'with uppercase resource ids' do
      let(:resource_ids) { [resource_id.upcase] }

      it 'verifies and names the downcased id' do
        expect(ar_client).to receive(:verify_repositories)
          .with(namespace_id: namespace_id, repository_ids: [resource_id])
          .and_return([])

        expect(lookup_objects).to contain_exactly({ id: resource_id, ancestor_ids: [namespace_id] })
      end
    end

    context 'with several resources' do
      let(:resource_ids) { [resource_id, other_resource_id, namespace_id] }

      it 'asks AR about the repositories once, and not about the namespace' do
        expect(ar_client).to receive(:verify_repositories).once.with(
          namespace_id: namespace_id,
          repository_ids: match_array([resource_id, other_resource_id])
        ).and_return([])

        expect(lookup_objects).to contain_exactly(
          { id: resource_id, ancestor_ids: [namespace_id] },
          { id: other_resource_id, ancestor_ids: [namespace_id] },
          { id: namespace_id, ancestor_ids: [] }
        )
      end
    end

    context 'when the resource is the namespace' do
      let(:resource_ids) { [namespace_id] }

      it 'names no ancestor and never calls AR' do
        expect(ar_client).not_to receive(:verify_repositories)

        expect(lookup_objects).to contain_exactly({ id: namespace_id, ancestor_ids: [] })
      end
    end

    context 'when the resource is the organization' do
      let(:resource_ids) { [organization.uuid] }

      it 'names no ancestor and never calls AR' do
        expect(ar_client).not_to receive(:verify_repositories)

        expect(lookup_objects).to contain_exactly({ id: organization.uuid, ancestor_ids: [] })
      end

      context 'with a repository' do
        let(:resource_ids) { [resource_id, organization.uuid] }

        it 'asks AR about the repository only' do
          expect(ar_client).to receive(:verify_repositories)
            .with(namespace_id: namespace_id, repository_ids: [resource_id])
            .and_return([])

          expect(lookup_objects).to contain_exactly(
            { id: resource_id, ancestor_ids: [namespace_id] },
            { id: organization.uuid, ancestor_ids: [] }
          )
        end
      end
    end

    context 'when AR says the repository is not in this namespace' do
      it 'names no ancestor, so IAM still requires a role on the repository' do
        allow(ar_client).to receive(:verify_repositories).and_return([resource_id])

        expect(lookup_objects).to contain_exactly({ id: resource_id, ancestor_ids: [] })
      end
    end

    context 'when AR rejects one of several repositories' do
      let(:resource_ids) { [resource_id, other_resource_id] }

      before do
        allow(ar_client).to receive(:verify_repositories).and_return([other_resource_id])
      end

      it 'names the namespace only for the verified repository' do
        expect(lookup_objects).to contain_exactly(
          { id: resource_id, ancestor_ids: [namespace_id] },
          { id: other_resource_id, ancestor_ids: [] }
        )
      end
    end

    context 'when AR cannot answer' do
      let(:resource_ids) { [resource_id, other_resource_id] }

      let(:outage) { ArtifactRegistry::Client::UnavailableError.new('down', status: 503) }
      let(:missing_credential) { ArtifactRegistry::Client::AuthorizationError.new('no credential') }
      let(:bad_batch) { ArgumentError.new('repository_ids must carry between 1 and 1000 entries') }

      where(:reason, :error) do
        [
          ['an outage', ref(:outage)],
          ['a missing credential', ref(:missing_credential)],
          ['a bad batch', ref(:bad_batch)]
        ]
      end

      with_them do
        it 'tracks it, names no ancestor, and still returns what IAM answers', :aggregate_failures do
          expect(ar_client).to receive(:verify_repositories).once.and_raise(error)
          expect(Gitlab::ErrorTracking).to receive(:track_exception).once
            .with(error, organization_id: organization.id, ar_namespace_id: namespace_id)

          expect(lookup_objects).to contain_exactly(
            { id: resource_id, ancestor_ids: [] },
            { id: other_resource_id, ancestor_ids: [] }
          )
        end
      end

      context 'when IAM then refuses the read' do
        before do
          allow(ar_client).to receive(:verify_repositories).and_raise(outage)
          allow(Gitlab::ErrorTracking).to receive(:track_exception)
        end

        it 'reports the refusal as unavailable, not as a denial', :aggregate_failures do
          allow(client).to receive(:lookup).and_raise(iam_error(:permission_denied))

          expect(execute).to be_error
          expect(execute.reason).to eq(:unavailable)
          expect(execute.message).to eq('The Artifact Registry service is unavailable.')
        end

        it 'keeps any other IAM reason' do
          allow(client).to receive(:lookup).and_raise(iam_error(:invalid_request))

          expect(execute.reason).to eq(:invalid_request)
        end
      end
    end

    context 'when AR verifies and IAM refuses the read' do
      it 'reports a denial' do
        allow(client).to receive(:lookup).and_raise(iam_error(:permission_denied))

        expect(execute.reason).to eq(:permission_denied)
      end
    end

    context 'when an input check fails' do
      let(:resource_ids) { [resource_id, 'not-a-uuid'] }

      it 'never calls AR', :aggregate_failures do
        expect(ar_client).not_to receive(:verify_repositories)
        expect(client).not_to receive(:lookup)

        expect(execute).to be_error
      end
    end
  end

  context 'when the organization has no Artifact Registry namespace' do
    it 'names no ancestor and never calls AR' do
      expect(ar_client).not_to receive(:verify_repositories)

      expect(lookup_objects).to contain_exactly({ id: resource_id, ancestor_ids: [] })
    end
  end

  context 'when the caller or inputs are invalid' do
    shared_examples 'a rejected lookup' do |message_fragment, reason|
      it 'returns an error and never calls the client', :aggregate_failures do
        expect(client).not_to receive(:lookup)

        result = execute
        expect(result).to be_error
        expect(result.message).to include(message_fragment)
        expect(result.reason).to eq(reason)
      end
    end

    context 'when there is no current user' do
      let(:current_user) { nil }

      it_behaves_like 'a rejected lookup', 'signed in', :signed_out
    end

    context 'when the organization is not set' do
      let(:organization) { nil }

      it_behaves_like 'a rejected lookup', 'Organization', nil
    end

    context 'when the caller is not a member of the organization' do
      let_it_be(:organization) { create(:organization) }

      # Generic not-found, so it does not disclose that another org exists.
      it_behaves_like 'a rejected lookup', 'could not be found', :not_found
    end

    context 'when the caller is a member of the organization but not owned by it' do
      let_it_be(:organization) { create(:organization) }
      let_it_be(:current_user) { create(:user) }

      before do
        create(:organization_user, organization: organization, user: current_user)
      end

      it 'performs the lookup', :aggregate_failures do
        expect(current_user.organization_id).not_to eq(organization.id)
        expect(client).to receive(:lookup).and_return(lookup_response)

        expect(execute).to be_success
      end
    end

    context 'when a resource id is nil' do
      let(:resource_ids) { [nil] }

      it_behaves_like 'a rejected lookup', 'Resource ID must be a valid UUIDv7.', :invalid_request
    end

    context 'when a resource id is not a UUID' do
      let(:resource_ids) { ['not-a-uuid'] }

      it_behaves_like 'a rejected lookup', 'UUIDv7', :invalid_request
    end

    # IAM only accepts UUIDv7 ids, so any other version is rejected here with a
    # precise message rather than failing at IAM with a generic invalid-request
    # error.
    context 'when a resource id is a UUIDv4' do
      let(:resource_ids) { ['c7a3b3f4-9d3a-4e46-9c3e-3a1f0b2d4e5f'] }

      it_behaves_like 'a rejected lookup', 'UUIDv7', :invalid_request
    end

    context 'when one role filter is unknown' do
      let(:roles) { [:not_a_role] }

      it_behaves_like 'a rejected lookup', 'Unknown roles', :invalid_request
    end

    context 'when several role filters are unknown' do
      let(:roles) { [:not_a_role, :also_bad] }

      it 'reports every unknown role in one error', :aggregate_failures do
        expect(client).not_to receive(:lookup)

        result = execute
        expect(result).to be_error
        expect(result.message).to include('not_a_role', 'also_bad')
        expect(result.reason).to eq(:invalid_request)
      end
    end
  end

  context 'when IAM returns an error' do
    # The client reports a transport reason; the service turns it into the
    # user-facing Artifact Registry message. Lambdas defer s_ to call time so
    # each helper receives a string literal.
    expected_messages = {
      not_found: -> { s_('ArtifactRegistry|The requested resources could not be found.') },
      permission_denied: -> { s_('ArtifactRegistry|You are not authorized to read these role assignments.') },
      unauthenticated: -> { s_('ArtifactRegistry|Could not authenticate with the Artifact Registry service.') },
      invalid_request: -> { s_('ArtifactRegistry|The role assignment lookup request was invalid.') },
      unavailable: -> { s_('ArtifactRegistry|The Artifact Registry service is unavailable.') },
      timeout: -> { s_('ArtifactRegistry|The Artifact Registry service did not respond in time.') },
      unknown: -> { s_('ArtifactRegistry|The role assignment lookup could not be completed.') }
    }

    it 'covers every reason the client can report' do
      client_reasons = Authn::IamService::LookupRelationshipsClient::STATUS_REASONS.values + [:unknown]

      expect(expected_messages.keys).to match_array(client_reasons)
    end

    expected_messages.each do |reason, expected_message|
      context "with the #{reason} reason" do
        before do
          allow(client).to receive(:lookup).and_raise(
            Authn::IamService::LookupRelationshipsClient::RequestError.new('diagnostic', reason: reason)
          )
        end

        it 'returns a service error with the mapped message and the client reason', :aggregate_failures do
          result = execute

          expect(result).to be_error
          expect(result.message).to eq(expected_message.call)
          expect(result.reason).to eq(reason)
        end
      end
    end
  end
end
