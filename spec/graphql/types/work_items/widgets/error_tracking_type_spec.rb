# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::WorkItems::Widgets::ErrorTrackingType, feature_category: :team_planning do
  include GraphqlHelpers

  it 'exposes the expected fields' do
    expected_fields = %i[type identifier stack_trace status]

    expect(described_class).to have_graphql_fields(*expected_fields)
  end

  describe '#status' do
    let_it_be(:project) { create(:project) }
    let_it_be(:user) { create(:user, developer_of: project) }
    let_it_be(:work_item) { create(:work_item, project: project) }
    let_it_be(:sentry_issue) { create(:sentry_issue, issue: work_item) }

    let(:widget) { WorkItems::Widgets::ErrorTracking.new(work_item) }
    let(:service) { instance_double(ErrorTracking::IssueLatestEventService, execute: service_response) }

    before do
      allow(ErrorTracking::IssueLatestEventService).to receive(:new).and_return(service)
    end

    subject(:status) { resolve_field(:status, widget, current_user: user) }

    context 'when the latest event is available' do
      let(:service_response) { { status: :success, latest_event: nil } }

      it { is_expected.to eq(:success) }
    end

    context 'when the latest event is not ready' do
      let(:service_response) { { status: :error, http_status: :no_content } }

      it { is_expected.to eq(:retry) }
    end

    context 'when the Sentry cache entry limit is reached' do
      let(:service_response) { { status: :error, http_status: :too_many_requests } }

      it { is_expected.to eq(:retry) }
    end

    context 'when the service fails' do
      let(:service_response) { { status: :error, http_status: :bad_request, message: 'error' } }

      it { is_expected.to eq(:error) }
    end
  end
end
