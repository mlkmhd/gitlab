# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::AdjournedDeletionService, feature_category: :groups_and_projects do
  let(:project) { create(:project, :aimed_for_deletion, marked_for_deletion_at: 10.days.ago).reload }

  let(:resource) { project }
  let(:destroy_worker) { ProjectDestroyWorker }
  let(:destroy_worker_params) { [project.id, user.id, {}] }
  let(:perform_method) { :perform_async }

  subject(:service) { described_class.new(project: project, current_user: user) }

  include_examples 'adjourned deletion service'

  context 'when the destroy is scheduled', :with_sidekiq_context do
    let(:user) { create(:user) }

    before do
      project.add_owner(user)
    end

    it 'returns a success response with destroy_scheduled' do
      allow(destroy_worker).to receive(perform_method)

      expect(service.execute.payload).to eq(destroy_scheduled: true)
    end
  end

  context 'when the restore fails', :with_sidekiq_context do
    let(:user) { nil }

    before do
      allow_next_instance_of(::Projects::RestoreService) do |restore_service|
        allow(restore_service).to receive(:execute).and_return(ServiceResponse.error(message: 'boom'))
      end
    end

    it 'logs the failure and returns the restore response', :aggregate_failures do
      expect(Gitlab::AppLogger).to receive(:warn).with(
        Labkit::Fields::LOG_MESSAGE => 'Adjourned project deletion could not restore project',
        Labkit::Fields::GL_PROJECT_ID => project.id,
        namespace_state: project.project_namespace.state_name.to_s,
        Labkit::Fields::ERROR_MESSAGE => 'boom'
      )

      result = service.execute

      expect(result).to be_error
      expect(result.message).to eq('boom')
    end
  end
end
