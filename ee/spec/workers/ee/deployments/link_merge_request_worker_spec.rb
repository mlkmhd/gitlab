# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Deployments::LinkMergeRequestWorker, feature_category: :continuous_integration do
  subject(:perform) { described_class.new.perform(deployment.id) }

  describe '#execute' do
    context 'when deployment is successful' do
      let(:deployment) { create(:deployment, :success) }

      it 'triggers dora watcher' do
        expect(Dora::Watchers).to receive(:process_event).with(deployment, :successful)

        perform
      end

      context 'when linking merge requests fails' do
        before do
          allow_next_instance_of(Deployments::LinkMergeRequestsService) do |service|
            allow(service).to receive(:execute).and_raise(StandardError)
          end
        end

        it 'does not trigger dora watcher' do
          expect(Dora::Watchers).not_to receive(:process_event)

          expect { perform }.to raise_error(StandardError)
        end
      end

      context 'when the project belongs to a non-default organization' do
        let_it_be(:project) { create(:project, :repository, organization: create(:organization)) }
        let(:deployment) { create(:deployment, :success, environment: create(:environment, project: project)) }

        it 'enqueues DORA metrics refresh within the organization context of the project' do
          expect(::Dora::DailyMetrics::RefreshWorker).to receive(:perform_async) do
            expect(Gitlab::ApplicationContext.current).to include(
              'meta.project' => project.full_path,
              'meta.organization_id' => project.organization_id
            )
          end

          perform
        end
      end
    end

    context 'with non-successful deployment' do
      let(:deployment) { create(:deployment, :canceled) }

      it 'does not trigger dora watcher' do
        expect(Dora::Watchers).not_to receive(:process_event)

        perform
      end
    end
  end

  shared_examples 'refreshes dora metrics for a successful deployment' do
    let(:deployment) { create(:deployment, :success) }
    let(:deployment_id) { deployment.id }

    it 'triggers dora watcher' do
      expect(Dora::Watchers).to receive(:process_event).with(deployment, :successful)

      exhausted
    end

    context 'when dora_metrics_refresh_once_per_deployment is disabled' do
      before do
        stub_feature_flags(dora_metrics_refresh_once_per_deployment: false)
      end

      it 'does not trigger dora watcher' do
        expect(Dora::Watchers).not_to receive(:process_event)

        exhausted
      end
    end

    context 'with non-successful deployment' do
      let(:deployment) { create(:deployment, :canceled) }

      it 'does not trigger dora watcher' do
        expect(Dora::Watchers).not_to receive(:process_event)

        exhausted
      end
    end

    context 'when the deployment does not exist' do
      let(:deployment_id) { non_existing_record_id }

      it 'does not trigger dora watcher' do
        expect(Dora::Watchers).not_to receive(:process_event)

        exhausted
      end
    end
  end

  describe '.sidekiq_retries_exhausted' do
    subject(:exhausted) do
      described_class.sidekiq_retries_exhausted_block.call({ 'args' => [deployment_id] }, StandardError.new)
    end

    it_behaves_like 'refreshes dora metrics for a successful deployment'
  end

  describe '.sidekiq_interruptions_exhausted' do
    subject(:exhausted) do
      described_class.interruptions_exhausted_block.call({ 'args' => [deployment_id] })
    end

    it_behaves_like 'refreshes dora metrics for a successful deployment'
  end
end
