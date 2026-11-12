# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::InsightsController, feature_category: :value_stream_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, developer_of: group) }

  let(:query_params) do
    {
      type: 'bar',
      query: {
        data_source: 'issuables',
        params: {
          issuable_type: 'issue',
          collection_labels: ['bug']
        }
      }
    }
  end

  before do
    stub_licensed_features(insights: true, dora4_analytics: true)

    login_as(user)
  end

  describe 'GET #show' do
    it_behaves_like 'contribution analytics charts configuration' do
      let_it_be(:insights_entity) { project }

      def run_request
        get namespace_project_insights_path(
          namespace_id: group,
          project_id: project,
          format: :json
        )
      end
    end

    context 'when the project filters out charts via projects.only' do
      let_it_be(:filtered_project) do
        create(:project, :custom_repo, group: group, files: {
          ::Gitlab::Insights::CONFIG_FILE_PATH => <<~YAML
            issuesCreated:
              title: Issues
              charts:
                - title: Issues
                  type: bar
                  projects:
                    only:
                      - -1 # non-existent project ID ensures chart is filtered out
                  query:
                    data_source: issuables
                    params:
                      issuable_type: issue
          YAML
        })
      end

      it 'renders the filter-out notice' do
        get namespace_project_insights_path(namespace_id: group, project_id: filtered_project)

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to include('Some items are not visible because the project was filtered out')
      end
    end

    context 'when the project has a structurally invalid insights.yml' do
      let_it_be(:bad_project) do
        create(:project, :custom_repo, group: group, files: {
          ::Gitlab::Insights::CONFIG_FILE_PATH => "Test_Insight:\n  - title: Testing yml\n    type: line\n"
        })
      end

      it 'renders the page with the invalid-config notice' do
        get namespace_project_insights_path(namespace_id: group, project_id: bad_project)

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to include(
          'The Insights configuration file (.gitlab/insights.yml) is not valid. ' \
            'Please correct it to load your insights.'
        )
      end

      it 'returns an empty config in the JSON endpoint' do
        get namespace_project_insights_path(namespace_id: group, project_id: bad_project, format: :json)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to eq({})
      end
    end

    context 'when the project has a partially valid insights.yml' do
      let_it_be(:partial_project) do
        create(:project, :custom_repo, group: group, files: {
          ::Gitlab::Insights::CONFIG_FILE_PATH => <<~YAML
            good:
              title: Good
              charts:
                - title: Issues
                  type: bar
                  query:
                    data_source: issuables
                    params:
                      issuable_type: issue
            broken:
              - title: Bad entry
          YAML
        })
      end

      it 'renders the invalid-config notice and surfaces the valid entries in JSON' do
        get namespace_project_insights_path(namespace_id: group, project_id: partial_project)

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to include(
          'The Insights configuration file (.gitlab/insights.yml) is not valid.'
        )

        get namespace_project_insights_path(namespace_id: group, project_id: partial_project, format: :json)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response.keys).to contain_exactly('good')
      end
    end
  end

  describe 'POST #query' do
    def run_request
      post query_namespace_project_insights_path(
        namespace_id: group,
        project_id: project,
        params: query_params,
        format: :json
      )
    end

    it 'succeeds' do
      run_request

      expect(response).to have_gitlab_http_status(:ok)
    end

    context 'when statement timeout happens' do
      it 'returns error response' do
        expect_next_instance_of(IssuesFinder) do |instance|
          expect(instance).to receive(:execute).and_raise(ActiveRecord::QueryCanceled)
        end

        run_request

        expect(response).to have_gitlab_http_status(:unprocessable_entity)

        expect(json_response['message']).to include('Try lowering the period_limit setting')
      end
    end

    context 'when issues match a chart without group_by' do
      let_it_be(:label_bug) { create(:label, project: project, title: 'bug') }

      before_all do
        create(:labeled_issue, project: project, labels: [label_bug])
        create(:labeled_issue, project: project, labels: [label_bug], created_at: 1.year.ago)
      end

      it 'counts only issues created in the last 180 days' do
        run_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['labels']).to eq(%w[bug undefined])
        expect(json_response['datasets'].first['data']).to eq([1, 0])
      end

      it 'preloads labels for every matching issuable' do
        run_request # first request of a session fills caches the control should not count
        control = ActiveRecord::QueryRecorder.new(skip_cached: false) { run_request }

        create_list(:labeled_issue, 3, project: project, labels: [label_bug])

        expect { run_request }.not_to exceed_all_query_limit(control)
      end

      context 'when insights_query_limits is disabled' do
        before do
          stub_feature_flags(insights_query_limits: false)
        end

        it 'keeps the finder preloads, which fail on the id-only select' do
          expect { run_request }.to raise_error(ActiveModel::MissingAttributeError)
        end
      end

      context 'with merged merge requests' do
        before_all do
          create(:labeled_merge_request, :merged, source_project: project, labels: [label_bug])
          create(:labeled_merge_request, :merged_last_month, source_project: project, labels: [label_bug],
            created_at: 200.days.ago)
        end

        before do
          query_params[:query][:params].merge!(issuable_type: 'merge_request', issuable_state: 'merged')
        end

        it 'counts merge requests created in the last 180 days' do
          run_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['datasets'].first['data']).to eq([1, 0])
        end

        it 'does not join merge request metrics' do
          recorder = ActiveRecord::QueryRecorder.new { run_request }

          expect(recorder.log.grep(/merge_request_metrics/)).to be_empty
        end
      end
    end

    context 'when period_limit is over the maximum' do
      before do
        query_params[:query][:params].merge!(group_by: 'month', period_limit: 37)
      end

      it 'returns error response' do
        run_request

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['message']).to include('Maximum for `:group_by` `month` is 36')
      end
    end

    context 'when projects.only has too many entries' do
      before do
        query_params[:projects] = { only: Array.new(101) { |i| i } }
      end

      it 'returns error response' do
        run_request

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['message']).to include('it can contain at most 100 entries')
      end
    end

    context 'with the rate limit', :clean_gitlab_redis_rate_limiting do
      let_it_be(:other_project) { create(:project, group: group) }

      before do
        stub_application_setting(insights_query_limit: 1)
      end

      it 'returns 429 with a JSON message after the limit' do
        run_request
        expect(response).to have_gitlab_http_status(:ok)

        run_request
        expect(response).to have_gitlab_http_status(:too_many_requests)
        expect(json_response['message']).to eq(Gitlab::ApplicationRateLimiter.throttled_error_message)
      end

      it 'counts each project separately' do
        run_request
        post query_namespace_project_insights_path(
          namespace_id: group, project_id: other_project, params: query_params, format: :json
        )

        expect(response).to have_gitlab_http_status(:ok)
      end
    end
  end
end
