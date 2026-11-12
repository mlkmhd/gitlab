# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dora::Watchers::DeploymentWatcher, feature_category: :devops_reports do
  describe ".mount" do
    context 'when deployment succeeded' do
      let(:deployment) { create(:deployment, :running) }

      it 'does not call for processing successful event' do
        expect(Dora::Watchers).not_to receive(:process_event)

        deployment.succeed!
      end

      it 'refreshes the metrics once after merge requests are linked', :freeze_time do
        expect(::Dora::DailyMetrics::RefreshWorker)
          .to receive(:perform_async).once.with(deployment.environment_id, Time.current.to_date.iso8601)
        expect(::Dora::DailyMetrics::RefreshWorker).not_to receive(:perform_in)

        deployment.succeed!
        Deployments::LinkMergeRequestWorker.new.perform(deployment.id)
      end

      context 'when dora_metrics_refresh_once_per_deployment is disabled' do
        before do
          stub_feature_flags(dora_metrics_refresh_once_per_deployment: false)
        end

        it 'calls for processing successful event' do
          expect(Dora::Watchers).to receive(:process_event).with(deployment, :successful)

          deployment.succeed!
        end
      end
    end
  end

  describe '#process' do
    subject { described_class.new(deployment, event) }

    let(:deployment) { create(:deployment, :success, finished_at: finished_at) }
    let(:finished_at) { 1.day.ago }
    let(:event) { :successful }

    it 'enqueues metric refresh for finished_at date' do
      expect(::Dora::DailyMetrics::RefreshWorker)
        .to receive(:perform_async).with(deployment.environment_id, finished_at.to_date.to_s)

      subject.process
    end

    context 'when the project belongs to a non-default organization' do
      let_it_be(:project) { create(:project, :repository, organization: create(:organization)) }
      let(:deployment) do
        create(:deployment, :success, finished_at: finished_at, environment: create(:environment, project: project))
      end

      it 'enqueues metric refresh within the organization context of the project' do
        expect(::Dora::DailyMetrics::RefreshWorker).to receive(:perform_async) do
          expect(Gitlab::ApplicationContext.current).to include(
            'meta.project' => project.full_path,
            'meta.organization_id' => project.organization_id
          )
        end

        subject.process
      end

      context 'when dora_metrics_refresh_once_per_deployment is disabled' do
        before do
          stub_feature_flags(dora_metrics_refresh_once_per_deployment: false)
        end

        it 'schedules metric refresh within the organization context of the project' do
          expect(::Dora::DailyMetrics::RefreshWorker).to receive(:perform_in) do
            expect(Gitlab::ApplicationContext.current).to include(
              'meta.project' => project.full_path,
              'meta.organization_id' => project.organization_id
            )
          end

          subject.process
        end
      end
    end

    context 'when dora_metrics_refresh_once_per_deployment is disabled' do
      before do
        stub_feature_flags(dora_metrics_refresh_once_per_deployment: false)
      end

      it 'schedules metric refresh for finished_at date' do
        expect(::Dora::DailyMetrics::RefreshWorker)
          .to receive(:perform_in).with(
            5.minutes,
            deployment.environment_id,
            finished_at.to_date.to_s)

        subject.process
      end
    end
  end
end
