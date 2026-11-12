# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::CycleAnalyticsController do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, maintainers: user) }

  before do
    sign_in(user)
  end

  context "counting page views for 'show'" do
    it_behaves_like 'internal event tracking' do
      let(:event) { 'view_cycle_analytics' }
      subject(:request) { get :show, params: { namespace_id: project.namespace, project_id: project } }
    end
  end

  context 'tracking visits to html page' do
    it_behaves_like 'tracking unique visits', :show do
      let(:request_params) { { namespace_id: project.namespace, project_id: project } }
      let(:target_id) { 'p_analytics_valuestream' }
    end

    it_behaves_like 'Snowplow event tracking with RedisHLL context' do
      subject { get :show, params: request_params, format: :html }

      let(:request_params) { { namespace_id: project.namespace, project_id: project } }
      let(:category) { described_class.name }
      let(:action) { 'perform_analytics_usage_action' }
      let(:namespace) { project.namespace }
      let(:label) { 'redis_hll_counters.analytics.analytics_total_unique_counts_monthly' }
      let(:property) { 'p_analytics_valuestream' }
    end
  end

  describe 'GET #show date range validation' do
    let(:cycle_analytics_params) { {} }
    let(:format) { :json }

    subject(:request) do
      get :show,
        params: { namespace_id: project.namespace, project_id: project, cycle_analytics: cycle_analytics_params },
        format: format
    end

    shared_examples 'a rejected date range' do
      it 'renders 422' do
        request

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['errors']['created_after'])
          .to include(s_('CycleAnalytics|The given date range is larger than 180 days'))
      end
    end

    context 'when the date range is within 180 days' do
      let(:cycle_analytics_params) { { created_after: 30.days.ago.to_date.to_s } }

      it 'renders 200' do
        request

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when created_after is more than 180 days ago and created_before is not given' do
      let(:cycle_analytics_params) { { created_after: '2010-01-01' } }

      it_behaves_like 'a rejected date range'
    end

    context 'when created_after and created_before are exactly 180 days apart' do
      let(:cycle_analytics_params) { { created_after: '2015-01-01', created_before: '2015-06-30' } }

      it 'renders 200' do
        request

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when created_after and created_before are 181 days apart' do
      let(:cycle_analytics_params) { { created_after: '2015-01-01', created_before: '2015-07-01' } }

      it_behaves_like 'a rejected date range'
    end

    shared_examples 'a rejected date' do |field|
      it 'renders 422' do
        request

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['errors'][field]).to include(I18n.t('errors.messages.invalid'))
      end
    end

    context 'when created_before is earlier than created_after' do
      let(:cycle_analytics_params) do
        { created_after: 10.days.ago.to_date.to_s, created_before: 20.days.ago.to_date.to_s }
      end

      it_behaves_like 'a rejected date', 'created_before'
    end

    context 'when created_after is in the future and created_before is not given' do
      let(:cycle_analytics_params) { { created_after: 10.days.from_now.to_date.to_s } }

      it_behaves_like 'a rejected date', 'created_before'
    end

    context 'when created_after is today in UTC and the instance time zone is behind UTC' do
      let(:cycle_analytics_params) { { created_after: '2026-11-09' } }

      around do |example|
        travel_to(Time.utc(2026, 11, 9, 3)) do
          Time.use_zone('America/Los_Angeles') { example.run }
        end
      end

      it 'renders 200' do
        request

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when created_after is not a date' do
      let(:cycle_analytics_params) { { created_after: 'not-a-date' } }

      it_behaves_like 'a rejected date', 'created_after'
    end

    context 'when created_after is longer than Date.parse accepts' do
      let(:cycle_analytics_params) { { created_after: "2015-01-01#{'x' * 200}" } }

      it_behaves_like 'a rejected date', 'created_after'
    end

    context 'when created_after is blank' do
      let(:cycle_analytics_params) { { created_after: '' } }

      it_behaves_like 'a rejected date', 'created_after'
    end

    context 'when created_before is not a date' do
      let(:cycle_analytics_params) { { created_after: 10.days.ago.to_date.to_s, created_before: 'not-a-date' } }

      it_behaves_like 'a rejected date', 'created_before'
    end

    context 'when only created_before is given and it is not a date' do
      let(:cycle_analytics_params) { { created_before: 'not-a-date' } }

      it_behaves_like 'a rejected date', 'created_before'
    end

    context 'when the format is HTML' do
      let(:cycle_analytics_params) { { created_after: '2010-01-01' } }
      let(:format) { :html }

      it 'renders 200' do
        request

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when the user is anonymous and the project is public' do
      let_it_be(:project) { create(:project, :public) }
      let(:cycle_analytics_params) { { created_after: '2010-01-01' } }

      before do
        sign_out(user)
      end

      it_behaves_like 'a rejected date range'
    end
  end

  include_examples GracefulTimeoutHandling
end
