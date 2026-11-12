# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Secrets Manager mutations resolving the entitlement for foreign namespaces',
  feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:groups) { create_list(:group, 6, :public) }
  let_it_be(:projects) { groups.map { |group| create(:project, :public, group: group) } }

  let(:principal) { 'principal: { type: USER, id: 1 }' }

  # Every mutation that includes `EnforcesWriteEntitlement`, keyed by the
  # namespace argument it resolves.
  let(:group_mutations) do
    {
      groupSecretCreate: 'name: "S", secret: "v", environment: "*", protected: false',
      groupSecretUpdate: 'name: "S", metadataCas: 1',
      groupSecretsManagerInitialize: '',
      groupSecretsManagerDeprovision: '',
      groupSecretsPermissionUpdate: "#{principal}, actions: [READ]",
      groupSecretsPermissionDelete: principal
    }
  end

  let(:project_mutations) do
    {
      projectSecretCreate: 'name: "S", secret: "v", environment: "*", branch: "*"',
      projectSecretUpdate: 'name: "S", metadataCas: 1',
      projectSecretsManagerInitialize: '',
      projectSecretsManagerDeprovision: '',
      projectSecretsPermissionUpdate: "#{principal}, actions: [READ]",
      projectSecretsPermissionDelete: principal
    }
  end

  # One request aliasing every mutation against foreign namespaces. Group and
  # project mutation `i` share root `groups[i]`. `Entitlement.for` is stubbed,
  # so this counts calls, not CustomersDot requests.
  let(:query) do
    aliased = group_mutations.each_with_index.map do |(name, args), i|
      aliased_mutation(name, i, %(groupPath: "#{groups[i].full_path}"), args)
    end

    aliased += project_mutations.each_with_index.map do |(name, args), i|
      aliased_mutation(name, i, %(projectPath: "#{projects[i].full_path}"), args)
    end

    "mutation { #{aliased.join("\n")} }"
  end

  let(:mutation_count) { group_mutations.size + project_mutations.size }

  def aliased_mutation(name, index, path_arg, args)
    input = [path_arg, args.presence].compact.join(', ')

    "#{name}#{index}: #{name}(input: { #{input} }) { errors }"
  end

  subject(:post_aliased_mutations) { post_graphql(query, current_user: current_user) }

  before do
    stub_licensed_features(native_secrets_management: true)
    enroll_instance_in_secrets_manager
    stub_secrets_manager_entitlement(state: :ineligible)
    # Twelve aliased mutations in one request, each loading its own namespace.
    allow(Gitlab::QueryLimiting::Transaction).to receive(:threshold).and_return(150)
  end

  it 'makes no entitlement lookups and fails each mutation as not found', :aggregate_failures do
    post_aliased_mutations

    expect(SecretsManagement::Entitlement).not_to have_received(:for)
    expect(graphql_errors.size).to eq(mutation_count)
    expect(graphql_errors.pluck('message'))
      .to all(eq(Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR))
  end

  context 'when the current user can read the Secrets Manager status' do
    before_all do
      projects.first.add_developer(current_user)
    end

    let(:query) do
      <<~GQL
        mutation { projectSecretCreate(input: {
          projectPath: "#{projects.first.full_path}", name: "S", secret: "v", environment: "*", branch: "*"
        }) { errors reason } }
      GQL
    end

    it 'still returns the structured denial reason' do
      post_aliased_mutations

      expect(graphql_data_at(:project_secret_create, :reason)).to eq('INELIGIBLE')
    end
  end

  context 'when secrets_manager_authorize_before_entitlement_lookup is disabled' do
    before do
      stub_feature_flags(secrets_manager_authorize_before_entitlement_lookup: false)
    end

    it 'looks up the entitlement once per aliased mutation' do
      post_aliased_mutations

      expect(SecretsManagement::Entitlement).to have_received(:for).exactly(mutation_count).times
    end
  end
end
