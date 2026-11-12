# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying the DAP Software Factory configuration of a project', :use_clean_rails_memory_store_caching,
  feature_category: :dap_triggers do
  include GraphqlHelpers

  let_it_be(:path) { Gitlab::Ai::DapFactory::Configuration::PATH }
  let_it_be(:group) { create(:group) }
  let_it_be_with_reload(:project) { create(:project, :custom_repo, group: group, files: { 'README.md' => 'readme' }) }
  let_it_be(:maintainer) { create(:user, maintainer_of: group) }
  let_it_be(:developer) { create(:user, developer_of: group) }
  let_it_be(:subscription_purchase) { create(:gitlab_subscription_add_on_purchase, :duo_core, :self_managed) }

  let(:current_user) { maintainer }
  let(:validated_content) { "factory: [test]\nowner: me\n" }
  let(:message_fields) { 'path code message' }
  let(:query) do
    graphql_query_for(:project, { full_path: project.full_path }, <<~FIELDS)
      dapFactoryConfiguration {
        path defaultBranch lastCommitId exists content
        errors { #{message_fields} }
        warnings { #{message_fields} }
        lastSync {
          status commitSha syncedAt
          errors { #{message_fields} }
          adoptedStages createdStages updatedStages deletedStages
          failedStages { #{message_fields} }
        }
        autoReview { available enabled decisionsEnabled locked }
      }
      dapFactoryConfigurationValidation(content: #{validated_content.to_json}) {
        valid
        errors { #{message_fields} }
        warnings { #{message_fields} }
      }
    FIELDS
  end

  let(:configuration) { graphql_data_at(:project, :dap_factory_configuration) }
  let(:validation) { graphql_data_at(:project, :dap_factory_configuration_validation) }

  before do
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    ::Ai::Setting.for_organization(project.organization).update!(duo_core_features_enabled: true)
    stub_ee_application_setting(duo_features_enabled: true)
    allow(::Gitlab::Duo::CodeReview).to receive(:available?).with(project).and_return(true)
    project.project_setting.update!(auto_duo_code_review_enabled: false, duo_code_review_decisions_enabled: false)
  end

  context 'when the file does not exist' do
    it 'says so and validates the given content' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(configuration).to eq(
        'path' => path,
        'defaultBranch' => project.default_branch,
        'lastCommitId' => nil,
        'exists' => false,
        'content' => nil,
        'errors' => [],
        'warnings' => [],
        'lastSync' => nil,
        'autoReview' => { 'available' => true, 'enabled' => false, 'decisionsEnabled' => false, 'locked' => false }
      )
      expect(validation['valid']).to be(false)
      expect(validation['errors']).to contain_exactly(
        hash_including('path' => 'factory', 'code' => 'invalid_factory')
      )
      expect(validation['warnings'].pluck('path')).to contain_exactly('owner')
    end
  end

  context 'when the file exists and was synced' do
    let_it_be(:file_content) { "factory: [test]\nowner: me\n" }
    let_it_be_with_reload(:project) do
      create(:project, :custom_repo, group: group, files: { 'README.md' => 'readme', path => file_content })
    end

    let_it_be(:file_commit_id) { project.repository.commit(project.default_branch).id }
    let_it_be(:head_commit_id) do
      project.repository.create_file(maintainer, 'other.txt', 'other', message: 'Touch another file',
        branch_name: project.default_branch)
    end

    let(:validated_content) { "factory: test\n" }
    let(:synced_at) { Time.zone.parse('2026-11-02T10:00:00Z') }

    before do
      Ai::DapFactory::SyncResult.new(
        status: 'partial', commit_sha: file_commit_id, synced_at: synced_at,
        errors: [{ 'path' => nil, 'code' => 'failed', 'message' => 'no' }],
        summary: { 'adopted' => %w[triage], 'created' => %w[plan], 'updated' => %w[build], 'deleted' => %w[verify],
                   'failed' => [{ 'stage' => 'review', 'message' => 'boom' }] }
      ).save(project) # rubocop:disable Rails/SaveBang -- not an ActiveRecord save
    end

    it 'returns the content, the commit that last changed the file, its problems and the last Sync' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(head_commit_id).not_to eq(file_commit_id)
      expect(configuration).to include(
        'exists' => true,
        'content' => file_content,
        'lastCommitId' => file_commit_id,
        'errors' => [{ 'path' => 'factory', 'code' => 'invalid_factory', 'message' => a_kind_of(String) }],
        'warnings' => [{ 'path' => 'owner', 'code' => 'unknown_key', 'message' => a_kind_of(String) }],
        'lastSync' => {
          'status' => 'PARTIAL',
          'commitSha' => file_commit_id,
          'syncedAt' => '2026-11-02T10:00:00Z',
          'errors' => [{ 'path' => nil, 'code' => 'failed', 'message' => 'no' }],
          'adoptedStages' => %w[triage],
          'createdStages' => %w[plan],
          'updatedStages' => %w[build],
          'deletedStages' => %w[verify],
          'failedStages' => [{ 'path' => 'stages.review', 'code' => 'sync_failed', 'message' => 'boom' }]
        }
      )
      expect(validation).to eq('valid' => true, 'errors' => [], 'warnings' => [])
    end
  end

  context 'when the user cannot update flow triggers' do
    let(:current_user) { developer }

    it 'returns nothing, without an error' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(configuration).to be_nil
      expect(validation).to be_nil
    end
  end

  context 'when the user cannot read the repository' do
    before do
      project.project_feature.update!(repository_access_level: ProjectFeature::DISABLED,
        merge_requests_access_level: ProjectFeature::DISABLED, builds_access_level: ProjectFeature::DISABLED)
    end

    it 'returns no configuration, but still validates content' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(configuration).to be_nil
      expect(validation).to include('valid' => false)
    end
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(dap_software_factory: false)
    end

    it 'returns nothing' do
      post_graphql(query, current_user: current_user)

      expect(configuration).to be_nil
      expect(validation).to be_nil
    end
  end

  context 'with a granular token' do
    let(:user) { maintainer }
    let(:boundary_object) { project }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

    it_behaves_like 'authorizing granular token permissions for GraphQL',
      [:read_project, :read_code, :update_ai_flow_trigger]

    it_behaves_like 'denying a granular token that only authorizes the parent of a field', :read_project do
      let(:parent_data_path) { [:project] }
      let(:field_data_path) { [:project, :dap_factory_configuration] }
    end

    it_behaves_like 'denying a granular token that only authorizes the parent of a field', :read_project do
      let(:parent_data_path) { [:project] }
      let(:field_data_path) { [:project, :dap_factory_configuration_validation] }
    end
  end
end
