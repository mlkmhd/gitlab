# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ErrorTracking::IssueLatestEventService, feature_category: :observability do
  include_context 'sentry error tracking context'

  let(:params) { { issue_id: '1' } }

  subject(:service) { described_class.new(project, user, params) }

  describe '#execute' do
    context 'with authorized user' do
      context 'when issue_latest_event returns an error event' do
        let(:error_event) { build(:error_tracking_sentry_error_event) }

        before do
          allow(error_tracking_setting)
            .to receive(:issue_latest_event).and_return(latest_event: error_event)
        end

        it 'returns the error event' do
          expect(result).to eq(status: :success, latest_event: error_event)
        end
      end

      context 'with a non-numeric issue_id' do
        let(:params) { { issue_id: '1/../abc' } }

        it 'returns bad request without calling Sentry' do
          expect(error_tracking_setting).not_to receive(:issue_latest_event)
          expect(result).to eq(message: 'Bad Request: Invalid issue_id', status: :error, http_status: :bad_request)
        end
      end

      context 'when the Sentry cache entry limit is reached' do
        before do
          allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?)
            .with(:error_tracking_sentry_cache_entries_per_user, scope: { user: user, project: project })
            .and_return(true)
        end

        it 'returns too many requests without calling Sentry or enqueuing a job' do
          expect(error_tracking_setting).not_to receive(:issue_latest_event)
          expect(Observability::ErrorTrackingReactiveCachingWorker).not_to receive(:perform_async)

          expect(result).to eq(
            status: :error,
            http_status: :too_many_requests,
            message: ::Gitlab::ApplicationRateLimiter.throttled_error_message
          )
        end
      end

      include_examples 'error tracking service data not ready', :issue_latest_event
      include_examples 'error tracking service sentry error handling', :issue_latest_event
      include_examples 'error tracking service http status handling', :issue_latest_event

      context 'with integrated error tracking' do
        let(:error_repository) { instance_double(Gitlab::ErrorTracking::ErrorRepository) }
        let(:params) { { issue_id: issue_id } }

        before do
          error_tracking_setting.update!(integrated: true)

          allow(service).to receive(:error_repository).and_return(error_repository)
        end

        context 'when error is found' do
          let(:error) { build_stubbed(:error_tracking_open_api_error, project_id: project.id) }
          let(:event) { build_stubbed(:error_tracking_open_api_error_event, fingerprint: error.fingerprint) }
          let(:issue_id) { error.fingerprint }

          before do
            allow(error_repository).to receive(:last_event_for).with(issue_id).and_return(event)
          end

          it 'returns the latest event in expected format' do
            expect(result[:status]).to eq(:success)
            expect(result[:latest_event]).to eq(event)
          end

          it 'does not check the Sentry cache entry limits' do
            expect(::Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)

            expect(result[:status]).to eq(:success)
          end
        end

        context 'with a non-numeric issue_id' do
          let(:event) { build_stubbed(:error_tracking_open_api_error_event) }
          let(:issue_id) { 'abc' }

          before do
            allow(error_repository).to receive(:last_event_for).with('abc').and_return(event)
          end

          it 'skips the Sentry id check and passes the id through' do
            expect(result[:status]).to eq(:success)
            expect(result[:latest_event]).to eq(event)
            expect(error_repository).to have_received(:last_event_for).with('abc')
          end
        end

        context 'when error does not exist' do
          let(:issue_id) { non_existing_record_id }

          before do
            allow(error_repository).to receive(:last_event_for).with(issue_id)
              .and_raise(Gitlab::ErrorTracking::ErrorRepository::DatabaseError.new('Error not found'))
          end

          it 'returns the error in detailed format' do
            expect(result).to match(
              status: :error,
              message: /Error not found/,
              http_status: :bad_request
            )
          end
        end
      end
    end

    include_examples 'error tracking service unauthorized user'
    include_examples 'error tracking service disabled'
  end
end
