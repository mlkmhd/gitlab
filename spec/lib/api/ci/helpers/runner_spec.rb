# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Ci::Helpers::Runner, feature_category: :runner_core do
  let(:helper) do
    Class.new do
      include API::Helpers
      include API::Ci::Helpers::Runner
      include Gitlab::RackLoadBalancingHelpers
    end.new
  end

  let(:env_hash) { {} }
  let(:request) { instance_double(Rack::Request, env: env_hash) }

  before do
    allow(helper).to receive(:request).and_return(request)
  end

  describe '#current_job', feature_category: :continuous_integration do
    let(:build) { create(:ci_build, :running) }

    it 'handles sticking of a build when a build ID is specified' do
      allow(helper).to receive(:params).and_return(id: build.id)

      expect(Ci::Build.sticking)
        .to receive(:find_caught_up_replica)
        .with(:build, build.id.to_s, hash_id: false)

      helper.current_job

      stick_object = env_hash[::Gitlab::Database::LoadBalancing::RackMiddleware::STICK_OBJECT].first
      expect(stick_object[0]).to eq(Ci::Build.sticking)
      expect(stick_object[1]).to eq(:build)
      expect(stick_object[2]).to eq(build.id.to_s)
    end

    it 'looks up the build once whether the id is the raw String or the coerced Integer' do
      allow(helper).to receive(:params).and_return({ id: build.id.to_s }, { id: build.id })

      expect(Ci::Build.sticking).to receive(:find_caught_up_replica).once

      2.times { helper.current_job }
    end

    it 'does not handle sticking if no build ID was specified' do
      allow(helper).to receive(:params).and_return({})

      expect(Ci::Build.sticking)
        .not_to receive(:find_caught_up_replica)

      helper.current_job
    end

    it 'returns the build if one could be found' do
      allow(helper).to receive(:params).and_return(id: build.id)

      expect(helper.current_job).to eq(build)
    end
  end

  describe '#current_runner', feature_category: :runner_core do
    let(:runner) { create(:ci_runner, token: 'foo') }

    it 'handles sticking of a runner if a token is specified' do
      allow(helper).to receive(:params).and_return(token: runner.token)

      expect(Ci::Runner.sticking)
        .to receive(:find_caught_up_replica)
        .with(:runner, runner.token, hash_id: false)

      helper.current_runner

      stick_object = env_hash[::Gitlab::Database::LoadBalancing::RackMiddleware::STICK_OBJECT].first
      expect(stick_object[0]).to eq(Ci::Runner.sticking)
      expect(stick_object[1]).to eq(:runner)
      expect(stick_object[2]).to eq(runner.token)
    end

    it 'does not handle sticking if no token was specified' do
      allow(helper).to receive(:params).and_return({})

      expect(Ci::Runner.sticking)
        .not_to receive(:find_caught_up_replica)

      helper.current_runner
    end

    it 'returns the runner if one could be found' do
      allow(helper).to receive(:params).and_return(token: runner.token)

      expect(helper.current_runner).to eq(runner)
    end
  end

  describe '#current_runner_from_header', feature_category: :runner_core do
    let_it_be(:runner) { create(:ci_runner, token: 'foo') }
    let(:headers_response) { { API::Ci::Helpers::Runner::RUNNER_TOKEN_HEADER => runner.token } }

    subject(:current_runner_from_header) { helper.current_runner_from_header }

    before do
      allow(helper).to receive(:headers).and_return(headers_response)
    end

    it 'returns the runner' do
      allow(helper).to receive(:headers).and_return(API::Ci::Helpers::Runner::RUNNER_TOKEN_HEADER => runner.token)

      is_expected.to eq(runner)
    end

    it 'handles sticking of a runner' do
      expect(Ci::Runner.sticking)
        .to receive(:find_caught_up_replica)
        .with(:runner, runner.token, hash_id: false)

      current_runner_from_header

      stick_object = env_hash[::Gitlab::Database::LoadBalancing::RackMiddleware::STICK_OBJECT].first
      expect(stick_object[0]).to eq(Ci::Runner.sticking)
      expect(stick_object[1]).to eq(:runner)
      expect(stick_object[2]).to eq(runner.token)
    end

    context 'when no token is specified' do
      let(:headers_response) { {} }

      it 'does not handle sticking' do
        expect(Ci::Runner.sticking).not_to receive(:find_caught_up_replica)

        current_runner_from_header
      end
    end

    context 'when specified token is invalid' do
      let(:headers_response) { { API::Ci::Helpers::Runner::RUNNER_TOKEN_HEADER => 'invalid' } }

      it { is_expected.to be_nil }
    end
  end

  describe '#authenticate_runner_from_header!', feature_category: :runner_core do
    let_it_be(:group, freeze: true) { create(:group) }
    let_it_be(:runner, freeze: true) { create(:ci_runner, :group, groups: [group]) }

    before do
      allow(helper).to receive_messages(
        headers: { API::Ci::Helpers::Runner::RUNNER_TOKEN_HEADER => runner.token },
        params: {}
      )
    end

    it 'sets Current.organization from the runner' do
      helper.authenticate_runner_from_header!

      expect(Gitlab::ApplicationContext.current).to include('meta.organization_id' => group.organization_id)
    end

    context 'with an instance runner' do
      let_it_be(:instance_runner, freeze: true) { create(:ci_runner, :instance) }

      before do
        allow(helper).to receive_messages(
          headers: { API::Ci::Helpers::Runner::RUNNER_TOKEN_HEADER => instance_runner.token },
          params: {}
        )
      end

      it 'does not set Current.organization' do
        helper.authenticate_runner_from_header!

        expect(Current.organization_assigned).to be_falsey
      end
    end
  end

  describe '#current_runner_manager', :freeze_time, feature_category: :fleet_visibility do
    let_it_be(:group) { create(:group) }

    let(:runner) { create(:ci_runner, :group, token: 'foo', groups: [group]) }

    subject(:current_runner_manager) { helper.current_runner_manager }

    context 'when no runner is found' do
      before do
        allow(helper).to receive(:params).and_return({})
      end

      it 'returns nil without creating a runner manager' do
        expect { current_runner_manager }.not_to change { Ci::RunnerManager.count }

        expect(current_runner_manager).to be_nil
      end
    end

    context 'when runner manager already exists' do
      let!(:existing_runner_manager) do
        create(:ci_runner_machine, runner: runner, system_xid: 'bar', contacted_at: 1.hour.ago)
      end

      before do
        allow(helper).to receive(:params).and_return(token: runner.token, system_id: existing_runner_manager.system_xid)
      end

      it { is_expected.to eq(existing_runner_manager) }

      it 'does not update the contacted_at field' do
        expect(current_runner_manager.contacted_at).to eq 1.hour.ago
      end
    end

    context 'when runner manager cannot be found' do
      it 'creates a new runner manager', :aggregate_failures do
        allow(helper).to receive(:params).and_return(token: runner.token, system_id: 'new_system_id')

        expect { current_runner_manager }.to change { Ci::RunnerManager.count }.by(1)

        expect(current_runner_manager).not_to be_nil
        current_runner_manager.reload

        expect(current_runner_manager.system_xid).to eq('new_system_id')
        expect(current_runner_manager.contacted_at).to be_nil
        expect(current_runner_manager.runner).to eq(runner)
        expect(current_runner_manager.runner_type).to eq(runner.runner_type)

        # Verify that a second call doesn't raise an error
        expect { helper.current_runner_manager }.not_to raise_error
        expect(Ci::RunnerManager.count).to eq(1)
      end

      it 'creates a new <legacy> runner manager if system_id is not specified', :aggregate_failures do
        allow(helper).to receive(:params).and_return(token: runner.token)

        expect { current_runner_manager }.to change { Ci::RunnerManager.count }.by(1)

        expect(current_runner_manager).not_to be_nil
        expect(current_runner_manager.system_xid).to eq(::API::Ci::Helpers::Runner::LEGACY_SYSTEM_XID)
        expect(current_runner_manager.runner).to eq(runner)
        expect(current_runner_manager.runner_type).to eq(runner.runner_type)
      end
    end

    describe 'runner manager creation limit' do
      let(:system_id) { 'new_system_id' }
      let(:throttled) { false }

      before do
        stub_application_setting(ci_runner_manager_creation_ceiling: 0)
        allow(helper).to receive(:params).and_return(token: runner.token, system_id: system_id)
        allow(request).to receive(:path).and_return('/api/v4/runners/verify')
        allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
        allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(:runner_manager_creation, scope: { ci_runner: runner })
          .and_return(throttled)
        allow(Gitlab::AppJsonLogger).to receive(:info)
        allow(::Gitlab::ApplicationRateLimiter).to receive(:log_request)
      end

      shared_examples 'creates the runner manager without logging' do
        it 'creates the runner manager without logging' do
          expect { current_runner_manager }.to change { Ci::RunnerManager.count }.by(1)

          expect(Gitlab::AppJsonLogger).not_to have_received(:info)
        end
      end

      context 'when both feature flags are disabled' do
        let(:throttled) { true }

        before do
          stub_feature_flags(log_runner_manager_creation_limit: false, enforce_runner_manager_creation_limit: false)
        end

        it 'does not check the limit' do
          current_runner_manager

          expect(::Gitlab::ApplicationRateLimiter)
            .not_to have_received(:throttled?).with(:runner_manager_creation, anything)
        end

        it_behaves_like 'creates the runner manager without logging'
      end

      context 'when only log_runner_manager_creation_limit is enabled' do
        before do
          stub_feature_flags(enforce_runner_manager_creation_limit: false)
        end

        it_behaves_like 'creates the runner manager without logging'

        context 'when the limit is exceeded' do
          let(:throttled) { true }

          it 'logs and still creates the runner manager' do
            expect { current_runner_manager }.to change { Ci::RunnerManager.count }.by(1)

            expect(Gitlab::AppJsonLogger).to have_received(:info).with(
              message: 'Runner manager creation limit exceeded',
              runner_id: runner.id,
              runner_type: runner.runner_type,
              system_xid: system_id,
              path: '/api/v4/runners/verify',
              limit: Gitlab::CurrentSettings.runner_manager_creation_limit,
              enforced: false
            )
            expect(::Gitlab::ApplicationRateLimiter).not_to have_received(:log_request)
          end
        end

        context 'when the runner manager already exists' do
          let(:throttled) { true }

          before do
            create(:ci_runner_machine, runner: runner, system_xid: system_id)
          end

          it 'does not check the limit' do
            expect { current_runner_manager }.not_to change { Ci::RunnerManager.count }

            expect(::Gitlab::ApplicationRateLimiter)
              .not_to have_received(:throttled?).with(:runner_manager_creation, anything)
          end
        end
      end

      context 'when only enforce_runner_manager_creation_limit is enabled' do
        before do
          stub_feature_flags(log_runner_manager_creation_limit: false)
        end

        it_behaves_like 'creates the runner manager without logging'

        context 'when the limit is exceeded' do
          let(:throttled) { true }

          before do
            allow(helper).to receive(:too_many_requests!).and_raise(StandardError, '429')
          end

          it 'logs and responds with too many requests without creating the runner manager' do
            expect { current_runner_manager }.to raise_error(StandardError, '429')

            expect(Ci::RunnerManager.count).to eq(0)
            expect(Gitlab::AppJsonLogger).to have_received(:info).with(a_hash_including(enforced: true))
            expect(::Gitlab::ApplicationRateLimiter)
              .to have_received(:log_request).with(request, :runner_manager_creation_request_limit, nil)
            expect(helper).to have_received(:too_many_requests!).with(
              { error: ::Gitlab::ApplicationRateLimiter.throttled_error_message },
              retry_after: 10.minutes
            )
          end

          context 'when system_id is not specified' do
            before do
              allow(helper).to receive(:params).and_return(token: runner.token)
            end

            it 'creates the <legacy> runner manager without checking the limit' do
              expect { current_runner_manager }.to change { Ci::RunnerManager.count }.by(1)

              expect(current_runner_manager.system_xid).to eq(::API::Ci::Helpers::Runner::LEGACY_SYSTEM_XID)
              expect(::Gitlab::ApplicationRateLimiter)
                .not_to have_received(:throttled?).with(:runner_manager_creation, anything)
            end
          end
        end
      end
    end

    describe 'runner manager creation ceiling', :clean_gitlab_redis_shared_state do
      let(:system_id) { 'new_system_id' }
      let(:reached) { true }

      before do
        stub_feature_flags(log_runner_manager_creation_limit: false, enforce_runner_manager_creation_limit: false)
        allow(helper).to receive(:params).and_return(token: runner.token, system_id: system_id)
        allow(request).to receive(:path).and_return('/api/v4/runners/verify')
        allow(::Ci::Runners::RunnerManagerCreationCeiling).to receive(:reached?).with(runner).and_return(reached)
        allow(Gitlab::AppJsonLogger).to receive(:info)
        allow(helper).to receive(:too_many_requests!).and_raise(StandardError, '429')
      end

      it 'logs and responds with too many requests without creating the runner manager' do
        expect { current_runner_manager }.to raise_error(StandardError, '429')

        expect(Ci::RunnerManager.count).to eq(0)
        expect(Gitlab::AppJsonLogger).to have_received(:info).with(
          Labkit::Fields::CLASS_NAME => helper.class.name,
          message: 'Runner manager creation ceiling exceeded',
          runner_id: runner.id,
          runner_type: runner.runner_type,
          system_xid: system_id,
          path: '/api/v4/runners/verify',
          limit: Gitlab::CurrentSettings.ci_runner_manager_creation_ceiling,
          enforced: true
        )
        expect(helper).to have_received(:too_many_requests!).with(
          { error: described_class::RUNNER_MANAGER_CREATION_CEILING_MESSAGE },
          retry_after: 10.minutes
        )
      end

      context 'when the runner has not reached the ceiling' do
        let(:reached) { false }

        it 'creates the runner manager without logging' do
          expect { current_runner_manager }.to change { Ci::RunnerManager.count }.by(1)

          expect(Gitlab::AppJsonLogger).not_to have_received(:info)
        end
      end

      context 'when the runner manager already exists' do
        let!(:existing_runner_manager) { create(:ci_runner_machine, runner: runner, system_xid: system_id) }

        it 'returns it without checking the ceiling' do
          expect(current_runner_manager).to eq(existing_runner_manager)

          expect(::Ci::Runners::RunnerManagerCreationCeiling).not_to have_received(:reached?)
        end
      end

      context 'when system_id is not specified' do
        before do
          allow(helper).to receive(:params).and_return(token: runner.token)
        end

        it 'creates the <legacy> runner manager without checking the ceiling' do
          expect { current_runner_manager }.to change { Ci::RunnerManager.count }.by(1)

          expect(::Ci::Runners::RunnerManagerCreationCeiling).not_to have_received(:reached?)
        end
      end

      context 'when only log_runner_manager_cap is enabled' do
        before do
          stub_feature_flags(enforce_runner_manager_ceiling: false)
        end

        it 'logs and still creates the runner manager' do
          expect { current_runner_manager }.to change { Ci::RunnerManager.count }.by(1)

          expect(Gitlab::AppJsonLogger).to have_received(:info)
            .with(a_hash_including(message: 'Runner manager creation ceiling exceeded', enforced: false))
        end
      end

      context 'when the feature flags are disabled' do
        before do
          stub_feature_flags(log_runner_manager_cap: false, enforce_runner_manager_ceiling: false)
        end

        it 'creates the runner manager without checking the ceiling' do
          expect { current_runner_manager }.to change { Ci::RunnerManager.count }.by(1)

          expect(::Ci::Runners::RunnerManagerCreationCeiling).not_to have_received(:reached?)
        end
      end

      context 'when the ceiling is 0' do
        before do
          stub_application_setting(ci_runner_manager_creation_ceiling: 0)
        end

        it 'creates the runner manager without checking the ceiling' do
          expect { current_runner_manager }.to change { Ci::RunnerManager.count }.by(1)

          expect(::Ci::Runners::RunnerManagerCreationCeiling).not_to have_received(:reached?)
        end
      end

      context 'when the creation limit is also exceeded' do
        before do
          stub_feature_flags(enforce_runner_manager_creation_limit: true)
          allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_return(true)
        end

        it 'responds with the ceiling error' do
          expect { current_runner_manager }.to raise_error(StandardError, '429')

          expect(helper).to have_received(:too_many_requests!).once
          expect(helper).to have_received(:too_many_requests!)
            .with({ error: described_class::RUNNER_MANAGER_CREATION_CEILING_MESSAGE }, anything)
        end
      end
    end
  end

  describe '#track_runner_authentication', :prometheus, feature_category: :runner_core do
    subject { helper.track_runner_authentication }

    let(:runner) { create(:ci_runner, token: 'foo') }

    it 'increments gitlab_ci_runner_authentication_success_total' do
      allow(helper).to receive(:params).and_return(token: runner.token)

      success_counter = ::Gitlab::Ci::Runner::Metrics.runner_authentication_success_counter
      failure_counter = ::Gitlab::Ci::Runner::Metrics.runner_authentication_failure_counter
      expect { subject }.to change { success_counter.get(runner_type: 'instance_type') }.by(1)
        .and not_change { success_counter.get(runner_type: 'project_type') }
        .and not_change { failure_counter.get }
    end

    it 'increments gitlab_ci_runner_authentication_failure_total' do
      allow(helper).to receive_messages(params: { token: 'invalid' }, headers: {})

      success_counter = ::Gitlab::Ci::Runner::Metrics.runner_authentication_success_counter
      failure_counter = ::Gitlab::Ci::Runner::Metrics.runner_authentication_failure_counter
      expect { subject }.to change { failure_counter.get }.by(1)
        .and not_change { success_counter.get(runner_type: 'instance_type') }
        .and not_change { success_counter.get(runner_type: 'project_type') }
    end

    context 'when token in headers' do
      it 'increments gitlab_ci_runner_authentication_success_total' do
        allow(helper).to receive_messages(
          headers: { API::Ci::Helpers::Runner::RUNNER_TOKEN_HEADER => runner.token },
          params: {}
        )

        success_counter = ::Gitlab::Ci::Runner::Metrics.runner_authentication_success_counter
        failure_counter = ::Gitlab::Ci::Runner::Metrics.runner_authentication_failure_counter
        expect { subject }.to change { success_counter.get(runner_type: 'instance_type') }.by(1)
          .and not_change { success_counter.get(runner_type: 'project_type') }
          .and not_change { failure_counter.get }
      end

      it 'increments gitlab_ci_runner_authentication_failure_total' do
        allow(helper).to receive_messages(
          headers: { API::Ci::Helpers::Runner::RUNNER_TOKEN_HEADER => 'invalid' },
          params: {}
        )

        success_counter = ::Gitlab::Ci::Runner::Metrics.runner_authentication_success_counter
        failure_counter = ::Gitlab::Ci::Runner::Metrics.runner_authentication_failure_counter
        expect { subject }.to change { failure_counter.get }.by(1)
          .and not_change { success_counter.get(runner_type: 'instance_type') }
          .and not_change { success_counter.get(runner_type: 'project_type') }
      end
    end
  end

  describe '#set_application_context' do
    let_it_be(:group, freeze: true) { create(:group) }
    let_it_be(:project, freeze: true) { create(:project, group: group) }
    let_it_be(:runner, freeze: true) { create(:ci_runner, :group, groups: [group]) }
    let_it_be(:build, freeze: true) { create(:ci_build, :running, runner: runner, project: project) }

    subject(:set_context) { helper.set_application_context }

    before do
      allow(helper).to receive(:params).and_return({})
    end

    context 'when current_job is present' do
      before do
        allow(helper).to receive_messages(params: { id: build.id, token: runner.token })
      end

      it 'pushes job and runner context and sets Current.organization' do
        set_context

        expect(Gitlab::ApplicationContext.current).to include(
          'meta.job_id' => build.id,
          'meta.organization_id' => group.organization_id
        )
      end
    end

    context 'when only current_runner is present' do
      before do
        allow(helper).to receive(:params).and_return(token: runner.token)
      end

      it 'pushes runner context and sets Current.organization' do
        set_context

        expect(Current.organization).to eq(Organizations::Organization.find(group.organization_id))
        expect(Gitlab::ApplicationContext.current).to include('meta.organization_id' => group.organization_id)
      end
    end

    context 'when neither job nor runner is present' do
      it 'does not push application context or set Current.organization' do
        expect(Gitlab::ApplicationContext).not_to receive(:push)

        set_context

        expect(Current.organization_assigned).to be_falsey
      end
    end
  end

  describe '#set_current_organization_from_runner' do
    let_it_be(:group, freeze: true) { create(:group) }
    let_it_be(:project, freeze: true) { create(:project, group: group) }

    subject(:set_current_organization) { helper.send(:set_current_organization_from_runner, runner) }

    context 'when runner is nil' do
      let(:runner) { nil }

      it 'does not set Current.organization' do
        set_current_organization

        expect(Current.organization_assigned).to be_falsey
      end
    end

    context 'with instance runner' do
      let(:runner) { build_stubbed(:ci_runner, :instance, organization_id: nil) }

      it 'does not set Current.organization' do
        set_current_organization

        expect(Current.organization_assigned).to be_falsey
      end
    end

    context 'with group runner' do
      let_it_be(:runner, freeze: true) { create(:ci_runner, :group, groups: [group]) }

      it 'sets Current.organization' do
        set_current_organization

        expect(Current.organization).to eq(Organizations::Organization.find(group.organization_id))
        expect(Gitlab::ApplicationContext.current).to include('meta.organization_id' => group.organization_id)
      end
    end

    context 'with project runner' do
      let_it_be(:runner, freeze: true) { create(:ci_runner, :project, projects: [project]) }

      it 'sets Current.organization' do
        set_current_organization

        expect(Current.organization).to eq(Organizations::Organization.find(project.organization_id))
        expect(Gitlab::ApplicationContext.current).to include('meta.organization_id' => project.organization_id)
      end
    end

    context 'when organization has been deleted' do
      let(:runner) { build_stubbed(:ci_runner, :group, organization_id: non_existing_record_id) }

      it 'assigns nil to Current.organization' do
        set_current_organization

        expect(Current.organization_assigned).to be true
        expect(Current.organization).to be_nil
      end
    end

    context 'when Current.organization is already assigned' do
      let_it_be(:runner, freeze: true) { create(:ci_runner, :group, groups: [group]) }
      let_it_be(:other_organization, freeze: true) { create(:organization) }

      before do
        Current.organization = other_organization
      end

      it 'does not overwrite the existing organization' do
        expect { set_current_organization }.not_to change { Current.organization }
      end
    end
  end

  describe '#set_current_organization_from_job' do
    let_it_be(:project) { create(:project) }
    let_it_be(:pipeline) { create(:ci_pipeline, project: project) }

    subject(:set_current_organization) { helper.send(:set_current_organization_from_job, job) }

    context 'with a job' do
      let_it_be(:job, freeze: true) { create(:ci_build, pipeline: pipeline) }

      it 'sets Current.organization to the job project organization' do
        set_current_organization

        expect(Current.organization).to eq(Organizations::Organization.find(project.organization_id))
        expect(Gitlab::ApplicationContext.current).to include('meta.organization_id' => project.organization_id)
      end
    end

    context 'when the job project has been deleted' do
      let(:job) { build_stubbed(:ci_build) }

      before do
        allow(job).to receive(:project).and_return(nil)
      end

      it 'does not set Current.organization' do
        set_current_organization

        expect(Current.organization_assigned).to be_falsey
      end
    end

    context 'when Current.organization is already assigned' do
      let_it_be(:job, freeze: true) { create(:ci_build, pipeline: pipeline) }
      let_it_be(:other_organization, freeze: true) { create(:organization) }

      before do
        Current.organization = other_organization
      end

      it 'does not overwrite the existing organization' do
        expect { set_current_organization }.not_to change { Current.organization }
      end
    end
  end

  describe '#check_if_backoff_required!' do
    subject { helper.check_if_backoff_required! }

    let(:backoff_runner) { false }

    before do
      allow(Gitlab::Database::Migrations::RunnerBackoff::Communicator)
        .to receive(:backoff_runner?)
        .and_return(backoff_runner)
    end

    context 'when migrations are running' do
      let(:backoff_runner) { true }

      it 'denies requests' do
        expect(helper).to receive(:too_many_requests!)

        subject
      end
    end

    context 'when migrations are not running' do
      let(:backoff_runner) { false }

      it 'allows requests' do
        expect(helper).not_to receive(:too_many_requests!)

        subject
      end
    end

    describe '#job_router_enabled?' do
      let_it_be(:group) { create(:group) }
      let_it_be(:project) { create(:project, group: group) }

      subject { helper.job_router_enabled?(runner) }

      context 'with instance runner' do
        let_it_be(:runner) { create(:ci_runner, :instance) }

        it { is_expected.to be true }

        context 'with feature flags' do
          where(:job_router, :job_router_instance_runners, :expected) do
            [
              [true,  true,  true],
              [true,  false, true],
              [false, true,  true],
              [false, false, false]
            ]
          end

          with_them do
            before do
              stub_feature_flags(
                job_router: job_router,
                job_router_instance_runners: job_router_instance_runners
              )
            end

            it { is_expected.to be expected }
          end
        end

        context 'and feature flag is enabled for specific runner only' do
          let(:specific_runner) { runner }

          before do
            stub_feature_flags(job_router_instance_runners: [specific_runner])
            stub_feature_flags(job_router: false)
          end

          it { is_expected.to be true }

          context 'when enabled for an unrelated runner' do
            let(:specific_runner) { create(:ci_runner, :instance) }

            it { is_expected.to be false }
          end
        end

        context 'and feature flag is enabled for single top-level group only' do
          before do
            stub_feature_flags(job_router_instance_runners: false)
            stub_feature_flags(job_router: [project.root_ancestor])
          end

          it { is_expected.to be false }
        end
      end

      context 'with group runner' do
        let_it_be(:runner) { create(:ci_runner, :group, groups: [group]) }

        it { is_expected.to be true }

        context 'and feature flag is globally disabled' do
          before do
            stub_feature_flags(job_router: false)
          end

          it { is_expected.to be false }
        end

        context 'and feature flag is enabled for specific group only' do
          before do
            stub_feature_flags(job_router: [group])
          end

          it { is_expected.to be true }
        end
      end

      context 'with project runner' do
        let_it_be(:runner) { create(:ci_runner, :project, projects: [project]) }

        it { is_expected.to be true }

        context 'and feature flag is globally disabled' do
          before do
            stub_feature_flags(job_router: false)
          end

          it { is_expected.to be false }
        end

        context 'and feature flag is enabled for group of project' do
          before do
            stub_feature_flags(job_router: [group])
          end

          it { is_expected.to be true }
        end

        context 'and feature flag is enabled for another project only' do
          let_it_be(:unrelated_project) { create(:project) }

          before do
            stub_feature_flags(job_router: [unrelated_project.root_ancestor])
          end

          it { is_expected.to be false }
        end
      end

      context 'with runner without owner' do
        let_it_be(:runner) { create(:ci_runner, :group, groups: [group]) }

        before do
          allow(runner).to receive(:owner).and_return(nil)
        end

        it { is_expected.to be true }

        context 'when feature flag is enabled for single top-level group only' do
          before do
            stub_feature_flags(job_router_instance_runners: false)
            stub_feature_flags(job_router: [group])
          end

          it { is_expected.to be false }
        end

        context 'when feature flag is disabled' do
          before do
            stub_feature_flags(job_router: false)
          end

          it { is_expected.to be false }
        end
      end
    end
  end

  describe '#ensure_job_router_enabled_for_runner!' do
    let_it_be(:runner) { create(:ci_runner, :instance) }

    let(:error_message) { 'Job Router is not available. Please contact your administrator.' }

    subject(:ensure_enabled) { helper.ensure_job_router_enabled_for_runner!(runner) }

    before do
      allow(Gitlab::Kas).to receive(:enabled?).and_return(true)
    end

    context 'when KAS is enabled and the Job Router is enabled for the runner' do
      it 'does not render an error' do
        expect(helper).not_to receive(:render_api_error!)

        ensure_enabled
      end
    end

    context 'when KAS is disabled' do
      before do
        allow(Gitlab::Kas).to receive(:enabled?).and_return(false)
      end

      it 'renders a 501 error' do
        expect(helper).to receive(:render_api_error!).with(error_message, 501)

        ensure_enabled
      end
    end

    context 'when the Job Router is disabled for the runner' do
      before do
        stub_feature_flags(job_router: false, job_router_instance_runners: false)
      end

      it 'renders a 501 error' do
        expect(helper).to receive(:render_api_error!).with(error_message, 501)

        ensure_enabled
      end
    end
  end
end
