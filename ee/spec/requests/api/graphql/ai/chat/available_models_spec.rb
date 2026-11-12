# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Getting Duo Chat available models', feature_category: :chat_engine do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { project.owner }

  let(:query) do
    <<~GQL
      query($projectId: ProjectID) {
        first: aiChatAvailableModels(projectId: $projectId) { defaultModel { ref } }
        second: aiChatAvailableModels(projectId: $projectId) { defaultModel { ref } }
      }
    GQL
  end

  before do
    allow(Ability).to receive(:allowed?).and_call_original
    allow(Ability).to receive(:allowed?).with(user, :access_duo_agentic_chat, anything).and_return(true)
    allow_next_instance_of(::Ai::FeatureSettingSelectionService) do |service|
      allow(service).to receive(:execute).and_return(ServiceResponse.success(payload: nil))
    end
  end

  it 'resolves the first call and rejects the second' do
    post_graphql(query, current_user: user, variables: { project_id: project.to_global_id.to_s })

    expect(graphql_errors).to contain_exactly(a_hash_including(
      'message' => '"aiChatAvailableModels" field can be requested only for 1 Query(s) at a time.'
    ))
  end
end
