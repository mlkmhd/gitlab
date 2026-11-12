# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Admin::Sidekiq, :clean_gitlab_redis_queues, feature_category: :shared do
  let_it_be(:admin) { create(:admin) }

  describe '/admin/sidekiq/concurrency_limits/:worker_class', :clean_gitlab_redis_queues_metadata do
    let(:worker) { AuthorizedProjectsWorker }
    let(:path) { "/admin/sidekiq/concurrency_limits/#{worker.name}" }
    let(:manager) do
      Gitlab::SidekiqMiddleware::ConcurrencyLimit::LimitManager.new(
        worker_name: worker.name,
        prefix: Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService::REDIS_KEY_PREFIX
      )
    end

    before do
      stub_feature_flags("disable_sidekiq_concurrency_limit_middleware_#{worker.name}": false)
      allow(worker).to receive_messages(get_concurrency_limit: 10, configured_concurrency_limit: 10)
      allow(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).to receive(:new)
        .and_wrap_original do |method, *args|
        method.call(*args).tap { |service| allow(service).to receive_messages(concurrent_worker_count: 3, queue_size: 50) }
      end
    end

    %w[Releases::CreateEvidenceWorker Releases%3A%3ACreateEvidenceWorker].each do |worker_path|
      context "with the namespaced worker path #{worker_path}" do
        let(:worker) { Releases::CreateEvidenceWorker }
        let(:path) { "/admin/sidekiq/concurrency_limits/#{worker_path}" }

        it 'reads, sets and clears the same worker override', :aggregate_failures do
          get api(path, admin, admin_mode: true)

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to include('worker_class' => worker.name, 'effective_limit' => 10)

          put api(path, admin, admin_mode: true), params: { limit: 20 }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to include('worker_class' => worker.name, 'effective_limit' => 20, 'override_limit' => 20)
          expect(manager.current_limit).to eq(20)

          delete api(path, admin, admin_mode: true)

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to include('worker_class' => worker.name, 'effective_limit' => 10, 'override_limit' => nil)
          expect(manager.override_active?).to be(false)
        end
      end
    end

    describe 'GET' do
      it_behaves_like 'GET request permissions for admin mode'

      it 'rejects unauthenticated requests' do
        get api(path)

        expect(response).to have_gitlab_http_status(:unauthorized)
      end

      it 'returns the limits and job counts', :aggregate_failures do
        manager.set_current_limit!(5)
        manager.set_override_limit!(20)

        get api(path, admin, admin_mode: true)

        expect(response).to have_gitlab_http_status(:ok)
        expect(response).to match_response_schema('public_api/v4/sidekiq_concurrency_limit')
        expect(json_response).to include(
          'worker_class' => worker.name, 'class_limit' => 10, 'effective_limit' => 20,
          'adaptive_limit' => 5, 'override_limit' => 20, 'running_jobs' => 3, 'deferred_jobs' => 50
        )
        expect(json_response['override_ttl']).to be_between(1, 1800)
      end

      it 'falls back to the class limit when Redis holds no adaptive or override value', :aggregate_failures do
        get api(path, admin, admin_mode: true)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include('class_limit' => 10, 'effective_limit' => 10,
          'adaptive_limit' => nil, 'override_limit' => nil, 'override_ttl' => nil)
      end

      it 'reports an unlimited effective limit when the middleware flag is disabled', :aggregate_failures do
        manager.set_override_limit!(20)
        stub_feature_flags(sidekiq_concurrency_limit_middleware: false)

        get api(path, admin, admin_mode: true)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include('effective_limit' => 0, 'override_limit' => 20,
          'middleware_enabled' => false)
      end

      it 'rejects unknown workers' do
        get api('/admin/sidekiq/concurrency_limits/String', admin, admin_mode: true)

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'rejects names that are not constant paths' do
        get api('/admin/sidekiq/concurrency_limits/foo', admin, admin_mode: true)

        expect(response).to have_gitlab_http_status(:bad_request)
      end

      context 'when the worker has no explicit limit' do
        before do
          allow(worker).to receive(:configured_concurrency_limit).and_return(nil)
        end

        it 'does not report a web-process default as the Sidekiq shard limit', :aggregate_failures do
          get api(path, admin, admin_mode: true)

          expect(response).to match_response_schema('public_api/v4/sidekiq_concurrency_limit')
          expect(json_response).to include('class_limit' => nil, 'effective_limit' => nil,
            'default_limit_requires_shard_context' => true)
        end

        it 'reports an unlimited default when shard-derived calculation is disabled', :aggregate_failures do
          stub_feature_flags(sidekiq_concurrency_limit_default_calculation: false)

          get api(path, admin, admin_mode: true)

          expect(json_response).to include('class_limit' => nil, 'effective_limit' => 0,
            'default_limit_requires_shard_context' => false)
        end

        it 'reports an override ahead of an unlimited default', :aggregate_failures do
          stub_feature_flags(sidekiq_concurrency_limit_default_calculation: false)
          manager.set_override_limit!(20)

          get api(path, admin, admin_mode: true)

          expect(json_response).to include('effective_limit' => 20, 'override_limit' => 20,
            'default_limit_requires_shard_context' => false)
        end
      end

      it 'reports a paused worker limit ahead of an override', :aggregate_failures do
        manager.set_override_limit!(20)
        allow(worker).to receive_messages(get_concurrency_limit: -1, configured_concurrency_limit: -1)

        get api(path, admin, admin_mode: true)

        expect(json_response).to include('class_limit' => -1, 'effective_limit' => -1, 'override_limit' => 20)
      end

      it 'reports an unlimited effective limit when the worker bypass flag is enabled', :aggregate_failures do
        manager.set_override_limit!(20)
        stub_feature_flags(disable_sidekiq_concurrency_limit_middleware_AuthorizedProjectsWorker: true)

        get api(path, admin, admin_mode: true)

        expect(json_response).to include('effective_limit' => 0, 'override_limit' => 20,
          'disabled_for_worker' => true)
      end

      it_behaves_like 'authorizing granular token permissions', :read_sidekiq_concurrency_limit do
        let(:boundary_object) { :instance }
        let(:user) { admin }
        let(:request) { get api(path, personal_access_token: pat) }
      end
    end

    describe 'PUT' do
      let(:params) { { limit: 20 } }

      it_behaves_like 'PUT request permissions for admin mode'

      it 'rejects unauthenticated mutations', :aggregate_failures do
        put api(path), params: params

        expect(response).to have_gitlab_http_status(:unauthorized)
        expect(manager.override_active?).to be(false)
      end

      it 'sets an override with a default TTL and logs the change', :aggregate_failures do
        allow(Gitlab::AppLogger).to receive(:info).and_call_original
        expect(Gitlab::AppLogger).to receive(:info).with(hash_including(
          Labkit::Fields::GL_USER_ID => admin.id,
          action: 'set',
          previous_override: { limit: nil, ttl: nil },
          override: { limit: 20, ttl: a_value_between(1, 1800) }
        )).and_call_original

        put api(path, admin, admin_mode: true), params: params

        expect(response).to have_gitlab_http_status(:ok)
        expect(response).to match_response_schema('public_api/v4/sidekiq_concurrency_limit')
        expect(manager.current_limit).to eq(20)
        expect(manager.override_status[:ttl]).to be_between(1, 1800)
      end

      it 'accepts an unlimited worker and a one-day TTL', :aggregate_failures do
        allow(worker).to receive_messages(get_concurrency_limit: 0, configured_concurrency_limit: 0)

        put api(path, admin, admin_mode: true), params: { limit: 2, ttl: 86400 }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include('class_limit' => 0, 'effective_limit' => 2, 'override_limit' => 2)
        expect(manager.current_limit).to eq(2)
        expect(manager.override_status[:ttl]).to be_between(1801, 86400)
      end

      it 'rejects an override while the middleware flag is disabled', :aggregate_failures do
        stub_feature_flags(sidekiq_concurrency_limit_middleware: false)

        put api(path, admin, admin_mode: true), params: params

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['message']).to include('sidekiq_concurrency_limit_middleware')
        expect(manager.override_active?).to be(false)
      end

      [{ limit: 0 }, { limit: -1 }, { limit: 2, ttl: 0 }, { limit: 2, ttl: 86401 }].each do |invalid_params|
        it "rejects #{invalid_params}", :aggregate_failures do
          put api(path, admin, admin_mode: true), params: invalid_params

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(manager.override_active?).to be(false)
        end
      end

      it 'rejects a paused worker', :aggregate_failures do
        allow(worker).to receive(:get_concurrency_limit).and_return(-1)

        put api(path, admin, admin_mode: true), params: params

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(manager.override_active?).to be(false)
      end

      it 'rejects a worker bypassed by the disable flag', :aggregate_failures do
        stub_feature_flags(disable_sidekiq_concurrency_limit_middleware_AuthorizedProjectsWorker: true)

        put api(path, admin, admin_mode: true), params: params

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['message']).to include('disable_sidekiq_concurrency_limit_middleware_AuthorizedProjectsWorker')
        expect(manager.override_active?).to be(false)
      end

      it 'rejects unknown workers' do
        put api('/admin/sidekiq/concurrency_limits/String', admin, admin_mode: true), params: params

        expect(response).to have_gitlab_http_status(:not_found)
      end

      context 'when the worker is the deferred-job resumer' do
        let(:worker) { ConcurrencyLimit::ResumeWorker }

        it 'rejects the override', :aggregate_failures do
          put api(path, admin, admin_mode: true), params: params

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to eq('400 Bad request - The deferred-job resumer cannot be limited')
          expect(manager.override_active?).to be(false)
        end
      end

      it_behaves_like 'authorizing granular token permissions', :update_sidekiq_concurrency_limit_override do
        let(:boundary_object) { :instance }
        let(:user) { admin }
        let(:request) { put api(path, personal_access_token: pat), params: params }
      end

      it 'rejects a granular token with only delete override permission', :aggregate_failures do
        token = create(:granular_pat, user: admin, boundary: Authz::Boundary.for(:instance),
          permissions: [:delete_sidekiq_concurrency_limit_override])

        put api(path, personal_access_token: token), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['error']).to eq('insufficient_granular_scope')
        expect(manager.override_active?).to be(false)
      end
    end

    describe 'DELETE' do
      it 'rejects unauthenticated resets', :aggregate_failures do
        manager.set_override_limit!(20)

        delete api(path)

        expect(response).to have_gitlab_http_status(:unauthorized)
        expect(manager.override_active?).to be(true)
      end

      it_behaves_like 'DELETE request permissions for admin mode' do
        let(:success_status_code) { :ok }
      end

      it 'clears the override, restores the adaptive limit and logs the change', :aggregate_failures do
        manager.set_current_limit!(5)
        manager.set_override_limit!(20)
        allow(Gitlab::AppLogger).to receive(:info).and_call_original
        expect(Gitlab::AppLogger).to receive(:info).with(hash_including(
          Labkit::Fields::GL_USER_ID => admin.id,
          action: 'reset',
          previous_override: { limit: 20, ttl: a_value_between(1, 1800) },
          override: { limit: nil, ttl: nil }
        )).and_call_original

        delete api(path, admin, admin_mode: true)

        expect(response).to have_gitlab_http_status(:ok)
        expect(response).to match_response_schema('public_api/v4/sidekiq_concurrency_limit')
        expect(json_response).to include('effective_limit' => 5, 'adaptive_limit' => 5, 'override_limit' => nil)
        expect(manager.override_active?).to be(false)
      end

      it 'rejects unknown workers' do
        delete api('/admin/sidekiq/concurrency_limits/String', admin, admin_mode: true)

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it_behaves_like 'authorizing granular token permissions', :delete_sidekiq_concurrency_limit_override do
        let(:boundary_object) { :instance }
        let(:user) { admin }
        let(:request) { delete api(path, personal_access_token: pat) }
      end

      it 'rejects a granular token with only update override permission', :aggregate_failures do
        manager.set_override_limit!(20)
        token = create(:granular_pat, user: admin, boundary: Authz::Boundary.for(:instance),
          permissions: [:update_sidekiq_concurrency_limit_override])

        delete api(path, personal_access_token: token)

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['error']).to eq('insufficient_granular_scope')
        expect(manager.override_status[:limit]).to eq(20)
      end
    end
  end

  describe 'DELETE /admin/sidekiq/queues/:queue_name' do
    context 'when the user is an admin' do
      around do |example|
        Gitlab::SidekiqSharding::Validator.allow_unrouted_sidekiq_calls do
          Sidekiq::Queue.new('authorized_projects').clear
        end

        Sidekiq::Testing.disable!(&example)

        Gitlab::SidekiqSharding::Validator.allow_unrouted_sidekiq_calls do
          Sidekiq::Queue.new('authorized_projects').clear
        end
      end

      def add_job(user, args)
        Gitlab::SidekiqSharding::Validator.allow_unrouted_sidekiq_calls do
          Sidekiq::Client.push(
            'class' => 'AuthorizedProjectsWorker',
            'queue' => 'authorized_projects',
            'args' => args,
            'meta.user' => user.username
          )
        end
      end

      context 'valid request' do
        before do
          add_job(admin, [1])
          add_job(admin, [2])
          add_job(create(:user), [3])
        end

        let_it_be(:path) { "/admin/sidekiq/queues/authorized_projects?user=#{admin.username}&worker_class=AuthorizedProjectsWorker" }

        it_behaves_like 'DELETE request permissions for admin mode' do
          let(:success_status_code) { :ok }
        end

        it 'returns info about the deleted jobs' do
          delete api(path, admin, admin_mode: true)

          expect(json_response).to eq('completed' => true, 'deleted_jobs' => 2, 'queue_size' => 1)
        end

        it_behaves_like 'authorizing granular token permissions', :drop_sidekiq_job do
          let(:boundary_object) { :instance }
          let(:user) { admin }
          let(:request) do
            delete api(path, personal_access_token: pat)
          end
        end
      end

      context 'when no required params are provided' do
        it 'returns a 400' do
          delete api("/admin/sidekiq/queues/authorized_projects?user_2=#{admin.username}", admin, admin_mode: true)

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when the queue does not exist' do
        it 'returns a 404' do
          delete api("/admin/sidekiq/queues/authorized_projects_2?user=#{admin.username}", admin, admin_mode: true)

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end
  end
end
