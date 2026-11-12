# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::CreateOrchestrationPolicyWorker, feature_category: :security_policy_management do
  describe '#perform' do
    let(:configuration) { create(:security_orchestration_policy_configuration, configured_at: configured_at) }

    subject(:worker) { described_class.new }

    context 'when newly created' do
      let(:configured_at) { nil }

      it 'schedules Security::SyncScanPoliciesWorker job' do
        expect(Security::SyncScanPoliciesWorker).to receive(:perform_debounced).with(configuration)

        worker.perform
      end
    end

    context 'with several outdated configurations' do
      before do
        allow(Security::SyncScanPoliciesWorker).to receive(:perform_debounced) do |config|
          config.source.root_ancestor
        end
      end

      it 'does not query the source per configuration' do
        create(:security_orchestration_policy_configuration, configured_at: nil)
        control = ActiveRecord::QueryRecorder.new { worker.perform }

        create_list(:security_orchestration_policy_configuration, 2, configured_at: nil)

        expect { worker.perform }.not_to exceed_query_limit(control)
      end
    end

    context 'when project has been updated earlier than configuration policy', :freeze_time do
      let(:configured_at) { 10.minutes.from_now }

      before do
        allow(configuration.security_policy_management_project).to receive(:last_repository_updated_at) { Time.current }
      end

      it 'does not schedules Security::SyncScanPoliciesWorker job' do
        expect(Security::SyncScanPoliciesWorker).not_to receive(:perform_debounced)

        worker.perform
      end
    end
  end
end
