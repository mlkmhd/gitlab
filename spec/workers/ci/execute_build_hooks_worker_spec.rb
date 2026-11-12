# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::ExecuteBuildHooksWorker, feature_category: :continuous_integration do
  let_it_be(:project, refind: true) { create(:project) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
  let_it_be(:build) { create(:ci_build, pipeline: pipeline) }

  let(:started_at) { 3.minutes.ago }

  let(:build_state) do
    {
      'build_status' => 'running',
      'build_started_at' => started_at,
      'build_finished_at' => nil,
      'build_duration' => nil
    }
  end

  it 'has a concurrency limit' do
    expect(described_class.get_max_concurrency_limit_percentage).to eq(0.45)
  end

  it_behaves_like 'a worker with a concurrency limit scope',
    type: :root_namespace, max_percentage: 0.2,
    feature_flag: :ci_pipeline_execution_concurrency_limit_scope_wave_three

  describe '#perform' do
    subject(:perform) { described_class.new.perform(project.id, build.id, build_state) }

    context 'when the project exists' do
      before do
        allow(Project).to receive(:find_by_id).with(project.id).and_return(project)
      end

      context 'with project hooks' do
        let!(:hook) { create(:project_hook, project: project, job_events: true) }

        it 'executes hooks with the build payload' do
          expect(project).to receive(:execute_hooks)
            .with(hash_including('object_kind' => 'build', 'build_id' => build.id), :job_hooks)

          perform
        end
      end

      context 'with project integrations' do
        let!(:integration) { create(:integration, active: true, job_events: true, project: project) }

        it 'executes integrations with the build payload' do
          expect(project).to receive(:execute_integrations)
            .with(hash_including('object_kind' => 'build', 'build_id' => build.id), :job_hooks)

          perform
        end
      end

      context 'without hooks or integrations' do
        it 'does not execute hooks or integrations' do
          expect(project).not_to receive(:execute_hooks)
          expect(project).not_to receive(:execute_integrations)

          perform
        end

        it 'does not load the build or build the payload', :aggregate_failures do
          expect(Ci::Build).not_to receive(:find_by_id)
          expect(Gitlab::DataBuilder::Build).not_to receive(:build)

          described_class.new.perform(project.id, build.id)
        end
      end

      context 'with hooks and integrations for other events' do
        let_it_be(:hook) { create(:project_hook, project: project, push_events: true, job_events: false) }
        let_it_be(:integration) { create(:integration, active: true, job_events: false, project: project) }

        it 'does not load the build or build the payload', :aggregate_failures do
          expect(Ci::Build).not_to receive(:find_by_id)
          expect(Gitlab::DataBuilder::Build).not_to receive(:build)

          described_class.new.perform(project.id, build.id)
        end
      end

      it 'builds the payload in the worker and pins the snapshot fields' do
        allow(project).to receive(:has_active_hooks?).and_return(true)

        expect(project).to receive(:execute_hooks) do |data, _hook_type|
          expect(data[:object_kind]).to eq('build')
          expect(data[:build_id]).to eq(build.id)
          expect(data[:build_status]).to eq('running')
          expect(data[:build_started_at]).to eq(started_at)
          expect(data[:build_started_at_iso]).to eq(started_at.iso8601)
          expect(data[:build_finished_at]).to be_nil
          expect(data[:build_finished_at_iso]).to be_nil
          expect(data[:build_duration]).to be_nil
        end

        perform
      end

      it 'derives the ISO timestamps when the values arrive as strings' do
        serialized = build_state.merge('build_started_at' => '2026-09-10T15:04:05Z')

        allow(project).to receive(:has_active_hooks?).and_return(true)

        expect(project).to receive(:execute_hooks) do |data, _hook_type|
          expect(data[:build_started_at_iso]).to eq('2026-09-10T15:04:05Z')
        end

        described_class.new.perform(project.id, build.id, serialized)
      end

      it 'keeps the whole webhook payload, not just the pinned fields', :aggregate_failures do
        allow(project).to receive(:has_active_hooks?).and_return(true)

        expect(project).to receive(:execute_hooks) do |data, _hook_type|
          expect(data.keys).to include(
            'commit', 'repository', 'project', 'runner', 'user', 'environment'
          )
          expect(data['commit']['sha']).to eq(pipeline.sha)
          expect(data['repository']['name']).to eq(project.name)
        end

        perform
      end

      it 'does nothing when the build no longer exists' do
        allow(project).to receive(:has_active_hooks?).and_return(true)

        expect(project).not_to receive(:execute_hooks)
        expect(project).not_to receive(:execute_integrations)

        described_class.new.perform(project.id, non_existing_record_id, build_state)
      end

      it 'ignores a job enqueued with a build payload hash' do
        allow(project).to receive(:has_active_hooks?).and_return(true)

        expect(Ci::Build).not_to receive(:find_by_id)
        expect(project).not_to receive(:execute_hooks)
        expect(project).not_to receive(:execute_integrations)

        described_class.new.perform(project.id, { 'build_id' => build.id, 'build_status' => 'running' })
      end

      it 'logs the pinned build status' do
        create(:project_hook, project: project, job_events: true)
        worker = described_class.new

        expect(worker).to receive(:log_extra_metadata_on_done).with(:build_status, 'running')

        worker.perform(project.id, build.id, build_state)
      end
    end

    context 'with Datadog integration' do
      let!(:datadog) do
        integration = create(:datadog_integration,
          project: project,
          active: true,
          datadog_site: 'datadoghq.com',
          api_key: 'test_api_key',
          datadog_ci_visibility: true)

        integration.update!(job_events: true)
        integration
      end

      it 'executes the Datadog integration with the build payload' do
        expect(Integrations::ExecuteWorker).to receive(:perform_async)
          .with(datadog.id, hash_including('object_kind' => 'build'))

        perform
      end
    end

    context 'when the project does not exist' do
      it 'does not look up the build' do
        expect(Ci::Build).not_to receive(:find_by_id)

        described_class.new.perform(non_existing_record_id, build.id, build_state)
      end
    end

    context 'when the commit cache is enabled but no cache lookup is needed' do
      let(:load_balancing_session) do
        Gitlab::Database::LoadBalancing::SessionMap.current(Project.load_balancer)
      end

      before do
        Gitlab::Database::LoadBalancing::SessionMap.clear_session
      end

      after do
        Gitlab::Database::LoadBalancing::SessionMap.clear_session
      end

      it 'keeps normal project routing for a build-ID job that skips the cache', :aggregate_failures do
        expect(Project).to receive(:find_by_id).with(project.id).once do
          expect(load_balancing_session.use_primary?).to be(false)
          project
        end

        described_class.new.perform(project.id, build.id)
      end
    end

    context 'when different pipelines use the same commit', :request_store, :clean_gitlab_redis_repository_cache do
      let_it_be(:project) { create(:project, :small_repo) }
      let_it_be(:hook) { create(:project_hook, project: project, job_events: true) }
      let_it_be(:sha) { project.repository.commit.id }
      let_it_be(:first_pipeline) { create(:ci_pipeline, :running, project: project, sha: sha, name: 'first') }
      let_it_be(:second_pipeline) { create(:ci_pipeline, :success, project: project, sha: sha, name: 'second') }
      let_it_be(:first_build) { create(:ci_build, pipeline: first_pipeline, name: 'first-job') }
      let_it_be(:second_build) { create(:ci_build, pipeline: second_pipeline, name: 'second-job') }

      let(:payloads) { [] }
      let(:commit_calls) { [] }

      def perform_in_fresh_context(job, state = {})
        RequestStore.end!
        RequestStore.clear!
        RequestStore.begin!
        BatchLoader::Executor.clear_current

        described_class.new.perform(project.id, job.id, state)
      end

      before do
        allow(Project).to receive(:find_by_id).and_wrap_original do |original, *args|
          original.call(*args).tap do |loaded_project|
            allow(loaded_project).to receive(:execute_hooks) { |data, _| payloads << data }
          end
        end

        allow(Gitlab::GitalyClient).to receive(:call).and_wrap_original do |original, *args, **kwargs, &block|
          commit_calls << args[3].oid.to_a if args[2] == :list_commits_by_oid
          original.call(*args, **kwargs, &block)
        end
      end

      shared_examples 'build hooks from separate worker contexts' do |expected_commit_calls|
        it 'keeps the event-specific payload with the expected Git lookup count', :aggregate_failures do
          [[first_build, 'running'], [second_build, 'success']].each do |job, status|
            perform_in_fresh_context(job, 'build_status' => status)
          end

          expect(commit_calls).to eq(Array.new(expected_commit_calls) { [sha] })
          expect(payloads.map { |data| data[:build_id] }).to eq([first_build.id, second_build.id])
          expect(payloads.map { |data| data[:build_status] }).to eq(%w[running success])
          expect(payloads.map { |data| data[:pipeline_id] }).to eq([first_pipeline.id, second_pipeline.id])
          expect(payloads.map { |data| data[:commit][:name] }).to eq(%w[first second])
          expect(payloads.map { |data| data[:commit][:status] }).to eq(%w[running success])
          expect(payloads.map { |data| data[:commit][:started_at] })
            .to eq([first_pipeline.started_at, second_pipeline.started_at])
          expect(payloads.map { |data| data[:commit][:sha] }).to eq([sha, sha])
          expect(payloads.first[:commit][:message]).to be_present
          expect(payloads.second[:commit][:message]).to eq(payloads.first[:commit][:message])
        end
      end

      context 'without the commit cache' do
        before do
          stub_feature_flags(ci_build_hook_commit_cache: false)
        end

        it_behaves_like 'build hooks from separate worker contexts', 2
      end

      context 'with the commit cache' do
        let(:commit_author) { User.find(project.creator_id) }

        before do
          stub_feature_flags(ci_build_hook_commit_cache: true)
        end

        it_behaves_like 'build hooks from separate worker contexts', 1

        it 'resolves the current author URL after the author is renamed', :aggregate_failures do
          original_url = Gitlab::Routing.url_helpers.user_url(commit_author)
          perform_in_fresh_context(first_build)

          commit_author.update!(username: "renamed-#{commit_author.id}")
          perform_in_fresh_context(second_build)

          expect(commit_calls).to eq([[sha]])
          expect(payloads.first[:commit][:author_url]).to eq(original_url)
          expect(payloads.second[:commit][:author_url]).to eq(Gitlab::Routing.url_helpers.user_url(commit_author))
        end

        it 'uses the mailing address after the author email is no longer confirmed', :aggregate_failures do
          original_url = Gitlab::Routing.url_helpers.user_url(commit_author)
          perform_in_fresh_context(first_build)

          commit_author.update!(confirmed_at: nil)
          perform_in_fresh_context(second_build)

          expect(commit_calls).to eq([[sha]])
          expect(payloads.first[:commit][:author_url]).to eq(original_url)
          expect(payloads.second[:commit][:author_url]).to eq("mailto:#{payloads.first[:commit][:author_email]}")
        end
      end
    end
  end
end
