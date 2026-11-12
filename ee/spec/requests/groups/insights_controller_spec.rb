# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::InsightsController, feature_category: :value_stream_management do
  let_it_be(:group) { create(:group) }

  before do
    stub_licensed_features(insights: true, dora4_analytics: true)

    login_as(user) if user
  end

  describe 'GET #show' do
    it_behaves_like 'contribution analytics charts configuration' do
      let_it_be(:insights_entity) { group }

      def run_request
        get group_insights_path(
          group_id: group,
          format: :json
        )
      end
    end

    context 'when the group insights config project has a structurally invalid insights.yml' do
      let_it_be(:user) { create(:user, reporter_of: group) }
      let_it_be(:config_project) do
        create(:project, :custom_repo, group: group, files: {
          ::Gitlab::Insights::CONFIG_FILE_PATH => "Test_Insight:\n  - title: Testing yml\n    type: line\n"
        })
      end

      before_all do
        group.create_insight!(project: config_project)
      end

      it 'renders the page with the invalid-config notice' do
        get group_insights_path(group_id: group)

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to include(
          'The Insights configuration file (.gitlab/insights.yml) is not valid. ' \
            'Please correct it to load your insights.'
        )
      end

      it 'returns an empty config in the JSON endpoint' do
        get group_insights_path(group_id: group, format: :json)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to eq({})
      end
    end

    context 'when the group insights config project has a partially valid insights.yml' do
      let_it_be(:user) { create(:user, reporter_of: group) }
      let_it_be(:config_project) do
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

      before_all do
        group.create_insight!(project: config_project)
      end

      it 'renders the invalid-config notice and surfaces the valid entries in JSON' do
        get group_insights_path(group_id: group)

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to include(
          'The Insights configuration file (.gitlab/insights.yml) is not valid.'
        )

        get group_insights_path(group_id: group, format: :json)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response.keys).to contain_exactly('good')
      end
    end
  end

  describe 'POST #query', :clean_gitlab_redis_rate_limiting do
    let_it_be(:public_group) { create(:group, :public) }
    let_it_be(:other_public_group) { create(:group, :public) }

    let(:user) { nil }
    let(:period_limit) { 30 }
    let(:query_params) do
      {
        type: 'bar',
        query: {
          data_source: 'issuables',
          params: { issuable_type: 'issue', group_by: 'day', period_limit: period_limit }
        }
      }
    end

    def run_request(group: public_group, ip: '1.2.3.4')
      post query_group_insights_path(group_id: group, params: query_params, format: :json),
        env: { 'REMOTE_ADDR' => ip }
    end

    before do
      stub_application_setting(insights_query_limit: 1)
    end

    context 'when an anonymous user queries a public group' do
      it 'returns 429 with a JSON message after the limit' do
        run_request
        expect(response).to have_gitlab_http_status(:ok)

        run_request
        expect(response).to have_gitlab_http_status(:too_many_requests)
        expect(json_response['message']).to eq(Gitlab::ApplicationRateLimiter.throttled_error_message)
      end

      it 'counts each IP address separately' do
        run_request
        run_request(ip: '5.6.7.8')

        expect(response).to have_gitlab_http_status(:ok)
      end

      it 'counts each group separately' do
        run_request
        run_request(group: other_public_group)

        expect(response).to have_gitlab_http_status(:ok)
      end

      context 'when period_limit is over the maximum' do
        let(:period_limit) { 1096 }

        it 'returns error response' do
          run_request

          expect(response).to have_gitlab_http_status(:unprocessable_entity)
          expect(json_response['message']).to include('Maximum for `:group_by` `day` is 1095')
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
    end

    context 'when a signed-in user queries from an IP address that anonymous users have rate limited' do
      it 'counts the user separately' do
        run_request

        login_as(create(:user))
        run_request

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when insights_query_limit is 0' do
      before do
        stub_application_setting(insights_query_limit: 0)
      end

      it 'does not rate limit' do
        2.times { run_request }

        expect(response).to have_gitlab_http_status(:ok)
      end
    end
  end
end
