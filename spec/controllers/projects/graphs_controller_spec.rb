# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::GraphsController, feature_category: :source_code_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :small_repo, maintainers: user) }

  before do
    sign_in(user)
  end

  describe '#show' do
    subject(:get_graph) { get(:show, params: params) }

    let(:params) { { namespace_id: project.namespace.path, project_id: project.path, id: 'master' } }

    describe 'ref_type' do
      it 'assigns ref_type' do
        get_graph

        expect(assigns[:languages]).to be_nil
      end

      context 'when ref_type is provided' do
        before do
          params[:ref_type] = 'heads'
        end

        it 'assigns ref_type' do
          get_graph

          expect(assigns[:ref_type]).to eq('heads')
        end
      end
    end

    describe 'when format is json' do
      let(:stubbed_limit) { 1 }

      before do
        params[:format] = 'json'
        stub_const('Projects::GraphsController::MAX_COMMITS', stubbed_limit)
      end

      it 'renders json without commit stats by default', :aggregate_failures do
        expect(Gitlab::Git::CommitStats).not_to receive(:new)

        get_graph

        expect(json_response.size).to eq(stubbed_limit)
        %w[id author_name author_email date].each do |key|
          expect(json_response[0]).to have_key(key)
        end
        expect(json_response[0]).not_to have_key('additions')
        expect(json_response[0]).not_to have_key('deletions')
      end

      context 'with caching', :use_clean_rails_memory_store_caching do
        let_it_be(:project) { create(:project, :repository, maintainers: user) }

        let(:repository) { project.repository }

        before do
          allow_next_found_instance_of(Project) do |found_project|
            allow(found_project).to receive(:repository).and_return(repository)
          end
        end

        # `get_graph` is a memoized subject, so repeat requests have to call `get` directly.
        it 'serves a repeated request for the same ref from the cache', :aggregate_failures do
          expect(repository).to receive(:commits).once.and_call_original

          get_graph
          first_body = response.body

          get(:show, params: params)

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.body).to eq(first_body)
        end

        it 'walks the commits again once the cache entry has expired', :aggregate_failures do
          expect(repository).to receive(:commits).twice.and_call_original

          get_graph
          first_body = response.body

          travel_to(described_class::CONTRIBUTOR_GRAPH_CACHE_EXPIRY.from_now + 1.second) do
            get(:show, params: params)
          end

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.body).to eq(first_body)
        end

        it 'caches the payload with and without commit stats separately', :aggregate_failures do
          expect(repository).to receive(:commits).twice.and_call_original

          get_graph
          expect(json_response[0]).not_to have_key('additions')

          get(:show, params: params.merge(with_stats: 'true'))
          expect(json_response[0]).to have_key('additions')
        end

        it 'does not reuse the cache for a ref that points at another commit', :aggregate_failures do
          expect(repository).to receive(:commits).twice.and_call_original

          get_graph
          master_id = json_response[0]['id']

          get(:show, params: params.merge(id: 'feature'))

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response[0]['id']).not_to eq(master_id)
        end

        it 'does not cache a Gitaly error and retries the walk on the next request', :aggregate_failures do
          original_commits = repository.method(:commits)
          expect(repository).to receive(:commits).twice.and_invoke(
            ->(*) { raise Gitlab::Git::CommandError, 'Gitaly unavailable' },
            ->(*args, **kwargs) { original_commits.call(*args, **kwargs) }
          )

          get_graph
          expect(response).to have_gitlab_http_status(:service_unavailable)

          get(:show, params: params)
          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response[0]).to have_key('id')
        end
      end

      context 'when commit stats are requested' do
        before do
          params[:with_stats] = 'true'
        end

        it 'renders json with commit stats', :aggregate_failures do
          expect(Gitlab::Git::CommitStats).not_to receive(:new)

          get_graph

          expect(json_response.size).to eq(stubbed_limit)
          %w[id author_name author_email date additions deletions].each do |key|
            expect(json_response[0]).to have_key(key)
          end
          expect(json_response[0]['additions']).to eq(1)
          expect(json_response[0]['deletions']).to eq(0)
        end

        context 'with multiple commits' do
          let_it_be(:project) { create(:project, :repository, maintainers: user) }

          it 'does not make a Gitaly request per commit for commit stats', :request_store, :aggregate_failures do
            gitaly_request_count_for_commit_limit(1)

            multiple_commits_request_count = gitaly_request_count_for_commit_limit(10)
            expect(json_response.size).to eq(10)

            single_commit_request_count = gitaly_request_count_for_commit_limit(1)
            expect(json_response.size).to eq(1)

            expect(multiple_commits_request_count - single_commit_request_count).to be <= 1
          end
        end

        context 'when serializing short stats' do
          using RSpec::Parameterized::TableSyntax

          let(:repository) { project.repository }
          let(:present_stats) { Gitaly::CommitStatInfo.new(additions: 5, deletions: 3) }

          where(:short_stats, :additions, :deletions) do
            ref(:present_stats) | 5 | 3
            nil                 | 0 | 0
          end

          with_them do
            let(:commit) do
              instance_double(
                Gitlab::Git::Commit,
                id: '5937ac0a7beb003549fc5fd26fc247adbce4a52e',
                author_name: 'Author',
                author_email: 'author@example.com',
                committed_date: Time.zone.parse('2024-01-01'),
                short_stats: short_stats
              )
            end

            before do
              allow(repository).to receive(:commits).and_return([commit])

              allow_next_found_instance_of(Project) do |found_project|
                allow(found_project).to receive(:repository).and_return(repository)
              end
            end

            it 'renders the expected counts', :aggregate_failures do
              get_graph

              expect(response).to have_gitlab_http_status(:ok)
              expect(json_response).to contain_exactly(
                'id' => commit.id,
                'author_name' => 'Author',
                'author_email' => 'author@example.com',
                'date' => '2024-01-01',
                'additions' => additions,
                'deletions' => deletions
              )
            end
          end
        end
      end
    end
  end

  def gitaly_request_count_for_commit_limit(limit)
    stub_const('Projects::GraphsController::MAX_COMMITS', limit)
    Gitlab::GitalyClient.reset_counts

    get(:show, params: params)

    Gitlab::GitalyClient.get_request_count
  end

  describe 'GET languages' do
    it "redirects_to action charts" do
      get(:languages, params: { namespace_id: project.namespace.path, project_id: project.path, id: 'master' })

      expect(response).to redirect_to action: :charts
    end
  end

  describe 'GET commits' do
    it "redirects_to action charts" do
      get(:commits, params: { namespace_id: project.namespace.path, project_id: project.path, id: 'master' })

      expect(response).to redirect_to action: :charts
    end
  end

  describe 'charts' do
    context 'with an anonymous user' do
      let(:project) { create(:project, :small_repo, :public) }

      before do
        sign_out(user)
      end

      it 'renders charts with 200 status code' do
        get(:charts, params: { namespace_id: project.namespace.path, project_id: project.path, id: 'master' })

        expect(response).to have_gitlab_http_status(:ok)
        expect(response).to render_template(:charts)
      end

      context 'when anonymous users can read build report results' do
        it 'sets the daily coverage options' do
          freeze_time do
            get(:charts, params: { namespace_id: project.namespace.path, project_id: project.path, id: 'master' })

            expect(assigns[:daily_coverage_options]).to eq(
              base_params: {
                start_date: Date.current - 90.days,
                end_date: Date.current,
                ref_path: project.repository.expand_ref('master'),
                param_type: 'coverage'
              },
              download_path: namespace_project_ci_daily_build_group_report_results_path(
                namespace_id: project.namespace,
                project_id: project,
                format: :csv
              ),
              graph_api_path: namespace_project_ci_daily_build_group_report_results_path(
                namespace_id: project.namespace,
                project_id: project,
                format: :json
              )
            )
          end
        end
      end

      context 'when anonymous users cannot read build report results' do
        before do
          project.update_column(:public_builds, false)

          get(:charts, params: { namespace_id: project.namespace.path, project_id: project.path, id: 'master' })
        end

        it 'does not set daily coverage options' do
          expect(assigns[:daily_coverage_options]).to be_nil
        end
      end

      it_behaves_like 'tracking unique visits', :charts do
        before do
          sign_in(user)
        end

        let(:request_params) { { namespace_id: project.namespace.path, project_id: project.path, id: 'master' } }
        let(:target_id) { 'p_analytics_repo' }
      end

      it_behaves_like 'Snowplow event tracking with RedisHLL context' do
        subject do
          sign_in(user)
          get :charts, params: request_params, format: :html
        end

        let(:request_params) { { namespace_id: project.namespace.path, project_id: project.path, id: 'master' } }
        let(:category) { described_class.name }
        let(:action) { 'perform_analytics_usage_action' }
        let(:namespace) { project.namespace }
        let(:label) { 'redis_hll_counters.analytics.analytics_total_unique_counts_monthly' }
        let(:property) { 'p_analytics_repo' }
      end
    end

    context 'when languages were previously detected' do
      let_it_be(:project) { create(:project, :small_repo, detected_repository_languages: true, maintainers: user) }
      let_it_be(:repository_language) { create(:repository_language, project: project) }

      it 'sets the languages properly' do
        get(:charts, params: { namespace_id: project.namespace.path, project_id: project.path, id: 'master' })

        expect(assigns[:languages]).to eq(
          [value: repository_language.share,
           label: repository_language.name,
           color: repository_language.color,
           highlight: repository_language.color])
      end
    end
  end

  describe 'when gitaly is unavailable', feature_category: :source_code_management do
    let(:params) do
      {
        namespace_id: project.namespace.to_param, project_id: project, id: 'master'
      }
    end

    before do
      allow(Gitlab::Git::Commit).to receive(:find)
        .and_raise(Gitlab::Git::CommandError, 'Gitaly unavailable')
    end

    describe 'GET #show' do
      it 'returns 503' do
        get :show, params: params

        expect(response).to have_gitlab_http_status(:service_unavailable)
      end

      it 'sets @gitaly_unavailable' do
        get :show, params: params

        expect(assigns[:gitaly_unavailable]).to be(true)
      end

      context 'with JSON format' do
        it 'returns 503 with JSON error' do
          get :show, params: params.merge(format: :json)

          expect(response).to have_gitlab_http_status(:service_unavailable)
          expect(json_response['error']).to be_present
        end
      end
    end

    describe 'GET #charts' do
      it 'returns 503' do
        get :charts, params: params

        expect(response).to have_gitlab_http_status(:service_unavailable)
      end

      it 'sets @gitaly_unavailable' do
        get :charts, params: params

        expect(assigns[:gitaly_unavailable]).to be(true)
      end
    end

    context 'when Gitaly health check fails (Commit.find returns nil)' do
      before do
        # Simulate Gitlab::Git::Commit.find swallowing the error and returning nil
        allow(Gitlab::Git::Commit).to receive(:find).and_return(nil)

        # Simulate Gitaly health check failing
        allow_next_instance_of(Gitlab::GitalyClient::HealthCheckService) do |service|
          allow(service).to receive(:check).and_return({ success: false, message: 'Gitaly unavailable' })
        end
      end

      it 'returns 503' do
        get :show, params: params

        expect(response).to have_gitlab_http_status(:service_unavailable)
      end

      it 'sets @gitaly_unavailable' do
        get :show, params: params

        expect(assigns[:gitaly_unavailable]).to be(true)
      end
    end
  end
end
