# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Ci::RunnerJobsResolver, feature_category: :fleet_visibility do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
  let_it_be(:irrelevant_pipeline) { create(:ci_pipeline, project: project) }

  let_it_be(:runner) { create(:ci_runner, :project, projects: [project]) }

  let_it_be(:build_one) { create(:ci_build, :success, name: 'Build One', runner: runner, pipeline: pipeline) }
  let_it_be(:build_two) { create(:ci_build, :success, name: 'Build Two', runner: runner, pipeline: pipeline) }
  let_it_be(:build_three) { create(:ci_build, :failed, name: 'Build Three', runner: runner, pipeline: pipeline) }
  let_it_be(:irrelevant_build) { create(:ci_build, name: 'Irrelevant Build', pipeline: irrelevant_pipeline) }

  describe '#resolve', :clean_gitlab_redis_rate_limiting do
    subject(:jobs) { resolve_jobs(args) }

    let(:args) { {} }

    context 'with authorized user', :enable_admin_mode do
      let(:current_user) { create(:user, :admin) }

      context 'with statuses argument' do
        let(:args) { { statuses: [Types::Ci::JobStatusEnum.coerce_isolated_input('SUCCESS')] } }

        it { is_expected.to contain_exactly(build_one, build_two) }

        context 'when the limit is exceeded without a request in the context' do
          before do
            stub_application_setting(runner_job_list_completed_statuses_limit_per_user: 1)
          end

          it 'returns an error' do
            resolve_jobs(args)

            expect_graphql_error_to_be_created(
              Gitlab::Graphql::Errors::ResourceNotAvailable,
              Gitlab::ApplicationRateLimiter.throttled_error_message
            ) { resolve_jobs(args) }
          end
        end

        context 'with a status a runner job cannot have' do
          # A runner never leaves its job pending, so this row only exists in specs
          let_it_be(:pending_build) { create(:ci_build, :pending, runner: runner, pipeline: pipeline) }

          let(:args) { { statuses: %w[SUCCESS PENDING].map { |s| Types::Ci::JobStatusEnum.coerce_isolated_input(s) } } }

          it { is_expected.to contain_exactly(build_one, build_two) }

          context 'when every status is one a runner job cannot have' do
            let(:args) { { statuses: [Types::Ci::JobStatusEnum.coerce_isolated_input('PENDING')] } }

            it 'returns no jobs without querying' do
              expect(::Ci::JobsFinder).not_to receive(:new)

              expect(jobs.nodes).to be_empty
            end
          end

          context 'when ci_rate_limit_runner_job_list_completed_statuses is disabled' do
            before do
              stub_feature_flags(ci_rate_limit_runner_job_list_completed_statuses: false)
            end

            it { is_expected.to contain_exactly(build_one, build_two, pending_build) }
          end
        end
      end

      context 'without statuses argument' do
        it { is_expected.to contain_exactly(build_one, build_two, build_three) }
      end
    end

    context 'with unauthorized user' do
      let(:current_user) { nil }

      it { is_expected.to be_nil }
    end
  end

  private

  def resolve_jobs(args = {}, context = { current_user: current_user })
    resolve(described_class, obj: runner, args: args, ctx: context)
  end
end
