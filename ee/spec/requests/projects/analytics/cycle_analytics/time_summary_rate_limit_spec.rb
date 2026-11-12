# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Project value stream analytics time summary rate limit', feature_category: :value_stream_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public, developers: user) }
  let_it_be(:other_project) { create(:project, :public, developers: user) }

  before do
    stub_licensed_features(cycle_analytics_for_projects: true)
  end

  describe 'GET /:namespace/:project/-/analytics/value_stream_analytics/time_summary' do
    it_behaves_like 'rate limited endpoint', rate_limit_key: :project_value_stream_analytics do
      let(:current_user) { user }

      before do
        sign_in(current_user)
      end

      def request
        get project_analytics_cycle_analytics_time_summary_path(project)
      end

      def request_with_second_scope
        get project_analytics_cycle_analytics_time_summary_path(other_project)
      end
    end
  end
end
