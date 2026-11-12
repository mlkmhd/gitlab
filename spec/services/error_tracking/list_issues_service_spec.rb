# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ErrorTracking::ListIssuesService, feature_category: :observability do
  include_context 'sentry error tracking context'
  include ReactiveCachingHelpers

  let(:params) { {} }

  subject(:service) { described_class.new(project, user, params) }

  describe '#execute' do
    context 'with Sentry backend' do
      let(:params) { { search_term: 'something', sort: 'last_seen', cursor: '1572959139000:0:0' } }

      let(:list_sentry_issues_args) do
        {
          issue_status: 'unresolved',
          limit: 20,
          search_term: 'something',
          sort: 'last_seen',
          cursor: '1572959139000:0:0'
        }
      end

      context 'with authorized user' do
        let(:issues) { [] }

        described_class::ISSUE_STATUS_VALUES.each do |status|
          it "returns the issues with #{status} issue_status" do
            params[:issue_status] = status
            list_sentry_issues_args[:issue_status] = status
            expect_list_sentry_issues_with(list_sentry_issues_args)

            expect(result).to eq(status: :success, pagination: {}, issues: issues)
          end
        end

        it 'returns the issues with no issue_status' do
          expect_list_sentry_issues_with(list_sentry_issues_args)

          expect(result).to eq(status: :success, pagination: {}, issues: issues)
        end

        it 'returns bad request with invalid issue_status' do
          params[:issue_status] = 'assigned'

          expect(error_tracking_setting).not_to receive(:list_sentry_issues)
          expect(result).to eq(message: "Bad Request: Invalid issue_status", status: :error, http_status: :bad_request)
        end

        it 'returns bad request with invalid sort' do
          params[:sort] = 'newest'

          expect(error_tracking_setting).not_to receive(:list_sentry_issues)
          expect(result).to eq(message: 'Bad Request: Invalid sort', status: :error, http_status: :bad_request)
        end

        it 'returns bad request when search_term is too long' do
          params[:search_term] = 'a' * (described_class::MAX_SEARCH_TERM_LENGTH + 1)

          expect(error_tracking_setting).not_to receive(:list_sentry_issues)
          expect(result).to eq(message: 'Bad Request: Invalid search_term', status: :error, http_status: :bad_request)
        end

        it 'returns bad request with a malformed cursor' do
          params[:cursor] = 'some-cursor'

          expect(error_tracking_setting).not_to receive(:list_sentry_issues)
          expect(result).to eq(message: 'Bad Request: Invalid cursor', status: :error, http_status: :bad_request)
        end

        context 'with the Sentry cache entry limit' do
          let(:throttled_result) do
            {
              status: :error,
              http_status: :too_many_requests,
              message: ::Gitlab::ApplicationRateLimiter.throttled_error_message
            }
          end

          before do
            stub_feature_flags(error_tracking_sentry_cache_entry_limit: true)
          end

          def stub_limits(per_user:, per_project: false)
            allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?)
              .with(:error_tracking_sentry_cache_entries_per_user, scope: { user: user, project: project })
              .and_return(per_user)
            allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?)
              .with(:error_tracking_sentry_cache_entries_per_project, scope: { project: project })
              .and_return(per_project)
          end

          it 'returns too many requests with no cache entry or job when the per-user limit is reached' do
            stub_limits(per_user: true)

            expect(error_tracking_setting).not_to receive(:list_sentry_issues)
            expect(Observability::ErrorTrackingReactiveCachingWorker).not_to receive(:perform_async)
            expect(::Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)
              .with(:error_tracking_sentry_cache_entries_per_project, anything)

            expect(result).to eq(throttled_result)
          end

          it 'returns too many requests when only the per-project limit is reached' do
            stub_limits(per_user: false, per_project: true)

            expect(error_tracking_setting).not_to receive(:list_sentry_issues)
            expect(result).to eq(throttled_result)
          end

          it 'calls Sentry when neither limit is reached' do
            stub_limits(per_user: false, per_project: false)
            expect_list_sentry_issues_with(list_sentry_issues_args)

            expect(result).to eq(status: :success, pagination: {}, issues: issues)
          end

          context 'when the cache entry is alive', :use_clean_rails_memory_store_caching do
            before do
              stub_reactive_cache(
                error_tracking_setting, { issues: issues, pagination: {} },
                'list_issues', list_sentry_issues_args.stringify_keys
              )
            end

            it 'does not count the read against the limits' do
              expect(::Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)

              expect(result).to eq(status: :success, pagination: {}, issues: issues)
            end
          end

          context 'with the real rate limiter', :clean_gitlab_redis_rate_limiting do
            let(:per_user_limit) do
              ::Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits
                .limit_for(:error_tracking_sentry_cache_entries_per_user)
            end

            before do
              allow(error_tracking_setting).to receive(:list_sentry_issues).and_return(issues: [], pagination: {})
            end

            def statuses_for(user, count)
              (1..count).map { |i| described_class.new(project, user, search_term: "term-#{i}").execute[:status] }
            end

            it 'throttles new entries per user and project, leaving other users unaffected' do
              expect(statuses_for(user, per_user_limit)).to all(eq(:success))

              expect(described_class.new(project, user, search_term: 'one-more').execute).to eq(throttled_result)

              other_user = create(:user, developer_of: project)
              expect(described_class.new(project, other_user, search_term: 'one-more').execute[:status]).to eq(:success)
            end

            context 'when the feature flag is disabled' do
              before do
                stub_feature_flags(error_tracking_sentry_cache_entry_limit: false)
              end

              it 'counts in log mode without throttling' do
                expect(statuses_for(user, per_user_limit + 1)).to all(eq(:success))
              end
            end
          end
        end

        include_examples 'error tracking service data not ready', :list_sentry_issues
        include_examples 'error tracking service sentry error handling', :list_sentry_issues
        include_examples 'error tracking service http status handling', :list_sentry_issues
      end

      include_examples 'error tracking service unauthorized user'
      include_examples 'error tracking service disabled'

      def expect_list_sentry_issues_with(list_sentry_issues_args)
        expect(error_tracking_setting)
          .to receive(:list_sentry_issues)
          .with(list_sentry_issues_args)
          .and_return(issues: [], pagination: {})
      end
    end

    context 'with integrated error tracking' do
      let(:error_repository) { instance_double(Gitlab::ErrorTracking::ErrorRepository) }
      let(:errors) { [] }
      let(:pagination) { Gitlab::ErrorTracking::ErrorRepository::Pagination.new(nil, nil) }
      let(:opts) { default_opts }

      let(:default_opts) do
        {
          filters: { status: described_class::DEFAULT_ISSUE_STATUS },
          query: nil,
          sort: described_class::DEFAULT_SORT,
          limit: described_class::DEFAULT_LIMIT,
          cursor: nil
        }
      end

      let(:params) { {} }

      before do
        error_tracking_setting.update!(integrated: true)

        allow(service).to receive(:error_repository).and_return(error_repository)
      end

      context 'when errors are found' do
        let(:error) { build_stubbed(:error_tracking_open_api_error, project_id: project.id) }
        let(:errors) { [error] }

        before do
          allow(error_repository).to receive(:list_errors)
            .with(**opts)
            .and_return([errors, pagination])
        end

        context 'without params' do
          it 'returns the errors without pagination' do
            expect(result[:status]).to eq(:success)
            expect(result[:issues]).to eq(errors)
            expect(result[:pagination]).to eq({})
            expect(error_repository).to have_received(:list_errors).with(**opts)
          end

          it 'does not check the Sentry cache entry limits' do
            stub_feature_flags(error_tracking_sentry_cache_entry_limit: true)
            expect(::Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)

            expect(result[:status]).to eq(:success)
          end
        end

        context 'with an opaque cursor' do
          let(:params) { { cursor: 'opaque-cursor' } }
          let(:opts) { default_opts.merge(cursor: 'opaque-cursor') }

          it 'passes the cursor through' do
            expect(result[:status]).to eq(:success)
            expect(error_repository).to have_received(:list_errors).with(**opts)
          end
        end

        context 'with pagination' do
          context 'with next page' do
            before do
              pagination.next = 'next cursor'
            end

            it 'has next cursor' do
              expect(result[:pagination]).to eq(next: { cursor: 'next cursor' })
            end
          end

          context 'with prev page' do
            before do
              pagination.prev = 'prev cursor'
            end

            it 'has prev cursor' do
              expect(result[:pagination]).to eq(previous: { cursor: 'prev cursor' })
            end
          end

          context 'with next and prev page' do
            before do
              pagination.next = 'next cursor'
              pagination.prev = 'prev cursor'
            end

            it 'has both cursors' do
              expect(result[:pagination]).to eq(
                next: { cursor: 'next cursor' },
                previous: { cursor: 'prev cursor' }
              )
            end
          end
        end
      end
    end
  end

  describe '#external_url' do
    it 'calls the project setting sentry_external_url' do
      expect(error_tracking_setting).to receive(:sentry_external_url).and_return(sentry_url)

      expect(subject.external_url).to eql sentry_url
    end
  end
end
