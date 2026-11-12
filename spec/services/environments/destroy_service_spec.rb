# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Environments::DestroyService, feature_category: :continuous_delivery do
  include CreateEnvironmentsHelpers

  let_it_be(:project) { create(:project, :private) }
  let_it_be(:user) { create(:user) }

  let(:service) { described_class.new(project, user) }

  describe '#execute' do
    subject { service.execute(environment) }

    let_it_be(:project) { create(:project, :private, :repository) }
    let_it_be(:developer) { create(:user, developer_of: project) }
    let_it_be(:reporter) { create(:user, reporter_of: project) }

    let(:user) { developer }

    let!(:environment) { create(:environment, project: project, state: :stopped) }

    context "when destroy is authorized" do
      it 'destroys the environment' do
        expect { subject }.to change { environment.destroyed? }.from(false).to(true)
      end

      context 'with deployments and job environments' do
        let!(:deployments) { create_list(:deployment, 2, :success, environment: environment, project: project) }
        let!(:job_environments) { create_list(:job_environment, 2, environment: environment, project: project) }

        let(:remaining_deployments) { Deployment.where(environment_id: environment.id) }
        let(:remaining_job_environments) { Environments::Job.where(environment_id: environment.id) }

        before do
          stub_const("#{described_class}::BATCH_SIZE", 1)
        end

        it 'deletes them in batches and destroys the environment', :aggregate_failures do
          deployments.each(&:create_ref)
          deployments.first.link_merge_requests(
            MergeRequest.id_in(create_list(:merge_request, 2, :merged, :unique_branches, source_project: project))
          )

          expect(Environments::Job).to receive(:delete_batch_for_environment).exactly(3).times.and_call_original
          expect(DeploymentMergeRequest).to receive(:each_batch_for_environment).and_call_original
          expect(Deployment).to receive(:fast_destroy_all).twice.and_call_original

          expect(subject).to be_success
          expect(environment).to be_destroyed
          expect(remaining_deployments).to be_empty
          expect(remaining_job_environments).to be_empty
          expect(DeploymentMergeRequest.where(environment_id: environment.id)).to be_empty
          expect(deployments.map { |deployment| project.commit(deployment.ref_path) }).to all(be_nil)
        end

        context 'when a request reaches its rows cap' do
          subject { delete_with_one_row_budget }

          def delete_with_one_row_budget
            service.unsafe_execute!(environment, budget: Environments::DestroyBudget.new(user: user, max_rows: 1))
          end

          it 'keeps the deleted rows and asks for a retry until the environment is gone', :aggregate_failures do
            expect(subject).to have_attributes(
              reason: :incomplete,
              message: _('The environment was partially deleted. Retry the request to finish deleting it.')
            )
            expect(remaining_job_environments.count).to eq(1)
            expect(Environment.exists?(environment.id)).to be(true)

            expect(Array.new(3) { delete_with_one_row_budget }.map(&:reason)).to eq([:incomplete, :incomplete, nil])
            expect(environment).to be_destroyed
          end
        end

        context 'when the rows cap is spent on the job environments' do
          before do
            deployments.first.link_merge_requests(
              MergeRequest.id_in(create(:merge_request, :merged, source_project: project))
            )
          end

          it 'keeps the merge request links for the retry', :aggregate_failures do
            budget = Environments::DestroyBudget.new(user: user, max_rows: 2)
            response = service.unsafe_execute!(environment, budget: budget)

            expect(response.reason).to eq(:incomplete)
            expect(remaining_job_environments).to be_empty
            expect(DeploymentMergeRequest.where(environment_id: environment.id).count).to eq(1)
          end
        end

        context 'when a concurrent request deletes the rows of a batch first' do
          before do
            calls = 0

            allow(Environments::Job).to receive(:delete_batch_for_environment).and_wrap_original do |method, *args|
              calls += 1
              next method.call(*args) unless calls == 1

              method.call(*args) # the concurrent request
              0
            end
          end

          it 'keeps deleting in batches before destroying the environment', :aggregate_failures do
            expect(subject).to be_success
            expect(environment).to be_destroyed
            # 0, then 1, then 0 rows
            expect(Environments::Job).to have_received(:delete_batch_for_environment).exactly(3).times
          end
        end

        context 'when the runtime budget is spent during the deployments' do
          before do
            allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
              allow(limiter).to receive(:over_time?) { remaining_deployments.count < deployments.size }
            end
          end

          it 'keeps the deleted rows and asks for a retry', :aggregate_failures do
            expect(subject.reason).to eq(:incomplete)
            expect(remaining_job_environments).to be_empty
            expect(remaining_deployments.count).to eq(1)
            expect(Environment.exists?(environment.id)).to be(true)
          end
        end

        context 'when the environment becomes available between batches' do
          before do
            allow(Environments::Job).to receive(:delete_batch_for_environment).and_wrap_original do |method, *args|
              Environment.id_in(environment).update_all(state: 'available')
              method.call(*args)
            end
          end

          it 'stops deleting and does not destroy the environment', :aggregate_failures do
            expect(subject).to have_attributes(
              reason: :not_stopped,
              message: _('Environment must be stopped before it can be deleted.')
            )
            expect(Environment.exists?(environment.id)).to be(true)
            expect(remaining_job_environments.count).to eq(1)
            expect(remaining_deployments.count).to eq(2)
          end
        end

        context 'when the environment becomes available during the deployment batches' do
          before do
            allow(Deployment).to receive(:fast_destroy_all).and_wrap_original do |method, *args|
              Environment.id_in(environment).update_all(state: 'available')
              method.call(*args)
            end
          end

          it 'keeps the deployments left', :aggregate_failures do
            expect(subject.reason).to eq(:not_stopped)
            expect(remaining_deployments.count).to eq(1)
          end
        end

        context 'when a concurrent request deletes the environment first' do
          before do
            allow(Environments::Job).to receive(:delete_batch_for_environment).and_wrap_original do |method, *args|
              Environment.id_in(environment).delete_all
              method.call(*args)
            end
          end

          it 'succeeds', :aggregate_failures do
            expect(subject).to be_success
            expect(Environment.exists?(environment.id)).to be(false)
          end
        end

        context 'with the rows rate limit', :clean_gitlab_redis_rate_limiting do
          before do
            stub_application_setting(environment_delete_rows_limit_per_user: 2)
          end

          def charge_rows(rows)
            Gitlab::ApplicationRateLimiter.throttled?(:environment_delete_rows, scope: { user: user }, cost: rows)
          end

          it 'stops at the limit and asks for a retry instead of exceeding it', :aggregate_failures do
            expect(subject.reason).to eq(:incomplete)
            expect(remaining_job_environments).to be_empty
            expect(remaining_deployments.count).to eq(2)
          end

          context 'when an earlier request deleted rows this minute' do
            before do
              charge_rows(1)
            end

            it 'stops at the batch that exceeds the limit and refuses the next request', :aggregate_failures do
              expect(subject).to have_attributes(
                reason: :throttled,
                message: Gitlab::ApplicationRateLimiter.throttled_error_message
              )
              expect(remaining_job_environments).to be_empty

              expect(Deployment).not_to receive(:fast_destroy_all)
              expect(service.execute(environment).reason).to eq(:throttled)
              expect(remaining_deployments.count).to eq(2)
            end

            context 'when the batch that exceeds the limit deletes the last rows' do
              before do
                stub_application_setting(environment_delete_rows_limit_per_user: 4)
              end

              it 'destroys the environment and refuses the next request', :aggregate_failures do
                expect(subject).to be_success
                expect(environment).to be_destroyed

                next_environment = create(:environment, project: project, state: :stopped)
                expect(service.execute(next_environment).reason).to eq(:throttled)
              end
            end
          end

          context 'when rate_limit_environment_delete_rows is disabled' do
            before do
              stub_feature_flags(rate_limit_environment_delete_rows: false)
            end

            it 'destroys the environment' do
              expect(subject).to be_success
            end
          end

          context 'without a user' do
            subject { described_class.new(project, nil).unsafe_execute!(environment) }

            it 'destroys the environment' do
              expect(subject).to be_success
            end
          end
        end
      end

      context 'when environment_delete_in_batches is disabled' do
        before do
          stub_feature_flags(environment_delete_in_batches: false)
        end

        it 'destroys the environment in one transaction', :aggregate_failures do
          create(:job_environment, environment: environment, project: project)

          expect(Environments::Job).not_to receive(:delete_batch_for_environment)

          expect(subject).to be_success
          expect(environment).to be_destroyed
        end
      end
    end

    context "when destroy is not authorized" do
      let(:user) { reporter }

      it 'does not destroy the environment' do
        expect { subject }.not_to change { environment.destroyed? }
      end
    end

    context "when destroy fails" do
      before do
        allow(environment)
          .to receive(:destroy)
          .and_return(false)
      end

      it 'returns errors' do
        expect(subject.message).to include("Attempted to destroy the environment but failed")
      end
    end
  end
end
