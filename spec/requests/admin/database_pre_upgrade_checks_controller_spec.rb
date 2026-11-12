# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Admin::DatabasePreUpgradeChecks', feature_category: :database do
  include AdminModeHelper

  let_it_be(:admin) { create(:admin) }
  let_it_be(:user) { create(:user) }

  shared_examples 'unauthorized request' do
    context 'when user is not an admin' do
      before do
        login_as(user)
      end

      it 'returns 404 response' do
        send_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when admin mode is disabled' do
      before do
        login_as(admin)
      end

      it 'redirects to admin mode enable' do
        send_request

        expect(response).to redirect_to(new_admin_session_path)
      end
    end
  end

  describe 'GET /admin/database_pre_upgrade_checks' do
    subject(:send_request) do
      get admin_database_pre_upgrade_checks_path
    end

    it_behaves_like 'unauthorized request'

    context 'when admin mode is enabled', :enable_admin_mode do
      before do
        login_as(admin)
      end

      it 'returns 200 response' do
        send_request

        expect(response).to have_gitlab_http_status(:ok)
      end

      it 'triggers an internal event and increments the unique user metric', :clean_gitlab_redis_shared_state do
        expect { send_request }
          .to trigger_internal_events('visit_db_pre_upgrade_checks_page')
          .with(user: admin, category: 'Admin::DatabasePreUpgradeChecksController')
          .and increment_usage_metrics(
            'redis_hll_counters.count_distinct_user_id_from_visit_db_pre_upgrade_checks_page_monthly',
            'redis_hll_counters.count_distinct_user_id_from_visit_db_pre_upgrade_checks_page_weekly'
          )
      end

      it 'points the checks at the database diagnostics endpoints' do
        send_request

        expect(response.body).to include(
          'data-run-schema-check-url="/admin/database_diagnostics/run_schema_check.json"',
          'data-schema-check-results-url="/admin/database_diagnostics/schema_check_results.json"',
          'data-run-lfk-backlog-check-url="/admin/database_diagnostics/run_lfk_backlog_check.json"',
          'data-lfk-backlog-check-results-url="/admin/database_diagnostics/lfk_backlog_check_results.json"'
        )
      end

      it 'embeds search path information as a data attribute', :aggregate_failures do
        information_payload = {
          databases: { 'main' => { search_path: '"$user", public', schemas: [] } }
        }

        expect(::Gitlab::Database::SearchPathInformation).to receive(:execute).and_return(information_payload)

        send_request

        expect(response.body).to include('data-search-path-information')
        expect(response.body).to include('&quot;search_path&quot;:&quot;\&quot;$user\&quot;, public&quot;')
      end
    end
  end
end
