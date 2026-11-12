# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::CycleAnalytics::EventsController do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, maintainers: user) }

  before do
    sign_in(user)
  end

  describe 'value stream analytics not set up flag' do
    context 'with no data' do
      it 'is empty' do
        get_issue

        expect(response).to be_successful
        expect(Gitlab::Json.parse(response.body)['events']).to be_empty
      end
    end

    context 'with data' do
      let(:milestone) { create(:milestone, project: project, created_at: 10.days.ago) }
      let(:issue) { create(:issue, project: project, created_at: 9.days.ago) }

      before do
        issue.update!(milestone: milestone)
      end

      it 'is not empty' do
        get_issue

        expect(response).to be_successful
      end

      it 'contains event detais' do
        get_issue

        events = Gitlab::Json.parse(response.body)['events']

        expect(events).not_to be_empty
        expect(events.first).to include('title', 'author', 'iid', 'total_time', 'created_at', 'url')
        expect(events.first['title']).to eq(issue.title)
      end

      context 'with data older than start date' do
        it 'is empty' do
          get_issue(additional_params: { cycle_analytics: { start_date: 7 } })

          expect(response).to be_successful

          expect(Gitlab::Json.parse(response.body)['events']).to be_empty
        end
      end
    end
  end

  describe 'date range validation' do
    context 'when the date range is within 180 days' do
      it 'renders 200' do
        get_issue(additional_params: { cycle_analytics: { created_after: 30.days.ago.to_date.to_s } })

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when the date range is longer than 180 days' do
      it 'renders 422' do
        get_issue(additional_params: { cycle_analytics: { created_after: '2010-01-01' } })

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['errors']['created_after'])
          .to include(s_('CycleAnalytics|The given date range is larger than 180 days'))
      end

      context 'when the format is HTML' do
        it 'renders 422' do
          get_issue(additional_params: { cycle_analytics: { created_after: '2010-01-01' } }, format: :html)

          expect(response).to have_gitlab_http_status(:unprocessable_entity)
        end
      end
    end

    context 'when created_before is earlier than created_after' do
      it 'renders 422' do
        get_issue(additional_params: {
          cycle_analytics: { created_after: 10.days.ago.to_date.to_s, created_before: 20.days.ago.to_date.to_s }
        })

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['errors']['created_before']).to include(I18n.t('errors.messages.invalid'))
      end
    end

    context 'when created_after is not a date' do
      it 'renders 422' do
        get_issue(additional_params: { cycle_analytics: { created_after: 'not-a-date' } })

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['errors']['created_after']).to include(I18n.t('errors.messages.invalid'))
      end

      context 'when the format is HTML' do
        it 'renders 422' do
          get_issue(additional_params: { cycle_analytics: { created_after: 'not-a-date' } }, format: :html)

          expect(response).to have_gitlab_http_status(:unprocessable_entity)
        end
      end
    end
  end

  include_examples GracefulTimeoutHandling

  def get_issue(additional_params: {}, format: :json)
    params = additional_params.merge(namespace_id: project.namespace, project_id: project)
    get(:issue, params: params, format: format)
  end
end
