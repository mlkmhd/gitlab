# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Project value stream analytics rate limit', feature_category: :value_stream_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public, developers: user) }
  let_it_be(:other_project) { create(:project, :public, developers: user) }

  shared_examples 'a rate limited value stream analytics endpoint' do
    context 'with a signed in user' do
      it_behaves_like 'rate limited endpoint', rate_limit_key: :project_value_stream_analytics do
        let(:current_user) { user }

        before do
          sign_in(current_user)
        end

        def request
          get path_for(project)
        end

        def request_with_second_scope
          get path_for(other_project)
        end
      end

      it 'limits by user and project' do
        sign_in(user)

        expect_rate_limit_scope({ user: user, project: project })

        get path_for(project)
      end
    end

    context 'without a signed in user' do
      it_behaves_like 'rate limited endpoint', rate_limit_key: :project_value_stream_analytics do
        def request
          get path_for(project), env: { REMOTE_ADDR: '1.2.3.4' }
        end

        def request_with_second_scope
          get path_for(project), env: { REMOTE_ADDR: '1.2.3.5' }
        end
      end

      it 'limits by IP and project' do
        expect_rate_limit_scope({ ip: '1.2.3.4', project: project })

        get path_for(project), env: { REMOTE_ADDR: '1.2.3.4' }
      end
    end
  end

  def expect_rate_limit_scope(scope)
    allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
    expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
      .with(:project_value_stream_analytics, hash_including(scope: scope))
      .and_call_original
  end

  describe 'GET /:namespace/:project/-/analytics/value_stream_analytics/summary' do
    def path_for(project)
      project_analytics_cycle_analytics_summary_path(project)
    end

    it_behaves_like 'a rate limited value stream analytics endpoint'
  end

  describe 'GET /:namespace/:project/-/value_stream_analytics.json' do
    def path_for(project)
      project_cycle_analytics_path(project, format: :json)
    end

    it_behaves_like 'a rate limited value stream analytics endpoint'

    context 'when the format is HTML' do
      it_behaves_like 'unthrottled endpoint', rate_limit_key: :project_value_stream_analytics do
        def request
          get project_cycle_analytics_path(project)
        end
      end
    end
  end

  describe 'GET /:namespace/:project/-/value_stream_analytics/events/issue.json' do
    def path_for(project)
      project_cycle_analytics_issue_path(project, format: :json)
    end

    it_behaves_like 'a rate limited value stream analytics endpoint'
  end
end
