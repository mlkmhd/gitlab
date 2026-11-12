# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EE::Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits,
  :clean_gitlab_redis_rate_limiting, :prometheus, feature_category: :rate_limiting do
  subject(:all) { Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits.all }

  describe '.all' do
    it 'merges EE-only keys on top of the CE registry' do
      expect(all).to include(
        :ai_catalog_config_validation,
        :ai_catalog_item_consumer_bulk_create,
        :ai_catalog_item_consumer_create,
        :ai_catalog_item_consumer_delete,
        :ai_catalog_item_report,
        :ai_model_selection_namespace_update,
        :ai_tool_rules_bulk_update,
        :ai_users_per_ip,
        :artifact_registry_namespace_provisioning,
        :audit_event_streaming_destination_mutation,
        :budget_cap_update_per_day,
        :budget_cap_update_per_hour,
        :budget_cap_update_per_minute,
        :card_fingerprint_phone_verification_transactions_limit,
        :code_suggestions_connection_details,
        :code_suggestions_direct_access,
        :container_scanning_for_registry_scans,
        :create_duo_otel_workflow,
        :credit_card_verification_check_for_reuse,
        :custom_dashboard_write,
        :dast_configuration_show,
        :dependency_management_scheduler_reschedule,
        :dependency_management_scheduler_run,
        :dependency_scanning_sbom_scan_api_download,
        :dependency_scanning_sbom_scan_api_throttling,
        :dependency_scanning_sbom_scan_api_upload,
        :dial_code_phone_verification_transactions_limit,
        :duo_code_review_mention,
        :duo_code_review_mention_limit_notice,
        :duo_workflow_direct_access,
        :duo_workflow_unauthorized_access,
        :hand_raise_lead_create,
        :hard_phone_verification_transactions_limit,
        :insights_query,
        :orbit_indexing_status,
        :orbit_item_counts,
        :orbit_query,
        :package_metadata,
        :partner_aws_api,
        :partner_gcp_api,
        :partner_postman_api,
        :refresh_billable_users,
        :secrets_manager_entitlement_refresh,
        :secrets_manager_initialize,
        :semantic_code_search_ad_hoc_indexing,
        :semantic_search_rate_limit,
        :soft_phone_verification_transactions_limit,
        :subscription_usage_per_day,
        :subscription_usage_per_hour,
        :subscription_usage_per_minute,
        :virtual_registries_endpoints_api_limit,
        :vulnerability_bulk_dismiss,
        :vulnerability_bulk_dismiss_hourly,
        :vulnerability_severity_override,
        :vulnerability_severity_override_hourly
      )
    end

    it 'preserves CE entries' do
      expect(all).to include(:pipelines_create, :ai_action, :web_hook_test)
    end

    # EE.rate_limits overrides the threshold/interval of these two CE keys, so
    # the registry must override their limit/period too while keeping the CE
    # structural fields (otherwise the new resolve-from-registry path would
    # diverge from the legacy hash under EE).
    it "overrides only the limit/period of CE keys that EE's rate_limits overrides", :aggregate_failures do
      supported_rate_limits = Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits

      expect(supported_rate_limits.limit_for(:code_suggestions_api_endpoint)).to eq(60)
      expect(supported_rate_limits.period_for(:code_suggestions_api_endpoint)).to eq(1.minute)

      expect(supported_rate_limits.limit_for(:geo_proxy)).to eq(3600)
      expect(supported_rate_limits.period_for(:geo_proxy)).to eq(1.minute)
    end

    it 'limits Artifact Registry handle claims to 10 an hour per organization', :aggregate_failures do
      supported_rate_limits = Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits

      expect(supported_rate_limits.limit_for(:artifact_registry_namespace_provisioning)).to eq(10)
      expect(supported_rate_limits.period_for(:artifact_registry_namespace_provisioning)).to eq(1.hour)
      expect(supported_rate_limits.rule_for(:artifact_registry_namespace_provisioning).characteristics)
        .to eq(%i[organization])
    end

    it 'stages secrets manager initializations per top-level group behind a feature flag', :aggregate_failures do
      supported_rate_limits = Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits
      root_namespace = build_stubbed(:group)

      expect(supported_rate_limits.limit_for(:secrets_manager_initialize)).to eq(30)
      expect(supported_rate_limits.period_for(:secrets_manager_initialize)).to eq(1.minute)
      expect(supported_rate_limits.rule_for(:secrets_manager_initialize).characteristics).to eq(%i[namespace])
      expect(supported_rate_limits).to be_staged(:secrets_manager_initialize)
      expect(supported_rate_limits.enforced?(:secrets_manager_initialize, { namespace: root_namespace })).to be(true)

      stub_feature_flags(secrets_manager_initialize_rate_limit: false)

      expect(supported_rate_limits.enforced?(:secrets_manager_initialize, { namespace: root_namespace })).to be(false)
    end

    describe 'secrets_manager_initialize counter', :freeze_time do
      let(:root_namespace) { build_stubbed(:group) }
      let(:other_root_namespace) { build_stubbed(:group) }

      def throttled?(namespace)
        Gitlab::ApplicationRateLimiter.throttled?(:secrets_manager_initialize, scope: { namespace: namespace })
      end

      def use_up_quota(namespace)
        Array.new(30) { throttled?(namespace) }
      end

      it 'blocks the 31st initialization in a minute for the same top-level group', :aggregate_failures do
        expect(use_up_quota(root_namespace)).to eq(Array.new(30, false))
        expect(throttled?(root_namespace)).to be(true)
      end

      it 'counts each top-level group separately' do
        use_up_quota(root_namespace)

        expect(throttled?(other_root_namespace)).to be(false)
      end

      context 'when the secrets_manager_initialize_rate_limit flag is disabled' do
        before do
          stub_feature_flags(secrets_manager_initialize_rate_limit: false)
        end

        it 'does not block initializations over the limit' do
          use_up_quota(root_namespace)

          expect(throttled?(root_namespace)).to be(false)
        end
      end
    end

    it 'reads the subscription usage limits from the application settings', :aggregate_failures do
      stub_application_setting(
        subscription_usage_per_minute_limit: 5,
        subscription_usage_per_hour_limit: 6,
        subscription_usage_per_day_limit: 7
      )
      supported_rate_limits = Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits

      {
        subscription_usage_per_minute: [5, 1.minute],
        subscription_usage_per_hour: [6, 1.hour],
        subscription_usage_per_day: [7, 1.day]
      }.each do |key, (limit, period)|
        expect(supported_rate_limits.limit_for(key)).to eq(limit)
        expect(supported_rate_limits.period_for(key)).to eq(period)
        expect(supported_rate_limits.rule_for(key).characteristics).to eq(%i[user])
        expect(supported_rate_limits.rule_for(key).action).to eq(:limit)
      end
    end

    it 'reads the budget cap updates limits from the application settings', :aggregate_failures do
      stub_application_setting(
        budget_cap_update_per_minute_limit: 5,
        budget_cap_update_per_hour_limit: 6,
        budget_cap_update_per_day_limit: 7
      )
      supported_rate_limits = Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits

      {
        budget_cap_update_per_minute: [5, 1.minute],
        budget_cap_update_per_hour: [6, 1.hour],
        budget_cap_update_per_day: [7, 1.day]
      }.each do |key, (limit, period)|
        expect(supported_rate_limits.limit_for(key)).to eq(limit)
        expect(supported_rate_limits.period_for(key)).to eq(period)
        expect(supported_rate_limits.rule_for(key).characteristics).to eq(%i[user])
        expect(supported_rate_limits.rule_for(key).action).to eq(:limit)
      end
    end

    it 'limits auto-remediation scheduler runs and reschedules to one per 5 minutes per project',
      :aggregate_failures do
      supported_rate_limits = Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits

      %i[dependency_management_scheduler_run dependency_management_scheduler_reschedule].each do |key|
        expect(supported_rate_limits.limit_for(key)).to eq(1)
        expect(supported_rate_limits.period_for(key)).to eq(5.minutes)
        expect(supported_rate_limits.rule_for(key).characteristics).to eq(%i[project])
      end
    end

    it 'reads the Orbit limits from the application settings', :aggregate_failures do
      stub_application_setting(orbit_query_limit: 5, orbit_indexing_status_limit: 6, orbit_item_counts_limit: 7)
      supported_rate_limits = Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits

      expect(supported_rate_limits.limit_for(:orbit_query)).to eq(5)
      expect(supported_rate_limits.limit_for(:orbit_indexing_status)).to eq(6)
      expect(supported_rate_limits.limit_for(:orbit_item_counts)).to eq(7)
    end

    it 'limits Insights queries per minute by user or IP and namespace, from the application settings',
      :aggregate_failures do
      stub_application_setting(insights_query_limit: 5)
      supported_rate_limits = Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits

      expect(supported_rate_limits.limit_for(:insights_query)).to eq(5)
      expect(supported_rate_limits.period_for(:insights_query)).to eq(1.minute)
      expect(supported_rate_limits.rule_for(:insights_query).characteristics).to eq(%i[user ip namespace])
    end

    it 'builds a cached limiter for an EE-only key' do
      limiter = Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits
        .limiter_for(:ai_catalog_item_report)

      expect(limiter).to be_a(::Labkit::RateLimit::Limiter)
      expect(limiter).to be(
        Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits.limiter_for(:ai_catalog_item_report)
      )
    end

    it 'builds limiters from EE-overridden CE registry values' do
      user = build_stubbed(:user)
      limiter = Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits
        .limiter_for(:code_suggestions_api_endpoint)

      60.times do
        expect(limiter.check({ user: user.id }).exceeded?).to be(false)
      end

      expect(limiter.check({ user: user.id }).exceeded?).to be(true)
    end

    it 'lets the labkit adapter dispatch an EE key through run!' do
      user = build_stubbed(:user)

      Gitlab::ApplicationRateLimiter::LabkitAdapter.run!(:ai_catalog_item_report, scope: { user: user })

      expected_key = "labkit:rl:{applimiter_ai_catalog_item_report" \
        ":limit_ai_catalog_item_reports_by_user:user:#{user.id}}"
      count = Gitlab::Redis::RateLimiting.with { |r| r.get(expected_key) }

      expect(count.to_i).to eq(1)
    end

    it 'gives an EE-only key the same synthetic bypass rule as CE keys', :aggregate_failures do
      user = build_stubbed(:user)

      result = Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits
        .limiter_for(:ai_catalog_item_report)
        .check({ user: user.id, bypass_header: '1' })

      expect(result.skipped?).to be(true)
      expect(result.rule.name).to eq('ai_catalog_item_report_bypass')

      count = Gitlab::Redis::RateLimiting.with do |r|
        r.get("labkit:rl:{applimiter_ai_catalog_item_report:limit_ai_catalog_item_reports_by_user:user:#{user.id}}")
      end
      expect(count).to be_nil
    end

    it 'does not skip an EE-only key for a Boolean bypass_header (only the exact string "1" matches)' do
      user = build_stubbed(:user)

      result = Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits
        .limiter_for(:ai_catalog_item_report)
        .check({ user: user.id, bypass_header: true })

      expect(result.skipped?).to be(false)
    end

    it 'routes a set-mode application key end-to-end as SADD/SCARD' do
      user = build_stubbed(:user)
      project_a = build_stubbed(:project)
      project_b = build_stubbed(:project)

      Gitlab::ApplicationRateLimiter::LabkitAdapter.run!(:unique_project_downloads_for_application,
        scope: { user: user }, context: { resource_id: project_a.id, threshold: 5, interval: 600 })
      Gitlab::ApplicationRateLimiter::LabkitAdapter.run!(:unique_project_downloads_for_application,
        scope: { user: user }, context: { resource_id: project_b.id, threshold: 5, interval: 600 })

      expected_key = "labkit:rl:{applimiter_unique_project_downloads_for_application" \
        ":limit_unique_project_downloads_by_user:user:#{user.id}}"
      members = Gitlab::Redis::RateLimiting.with { |r| r.smembers(expected_key) }

      expect(members).to contain_exactly(project_a.id.to_s, project_b.id.to_s)
    end

    # Regression guard for the BaseThrottleService flow: initialize calls
    # rate_limited?(peek: true) and execute calls rate_limited?, so every
    # request invokes the same key twice. If peek accidentally SADDed, the
    # Redis SET would carry 2x cardinality per request and ban users at
    # half the configured threshold.
    it 'does not SADD on peek when both peek and check share the same call site' do
      user = build_stubbed(:user)
      project = build_stubbed(:project)
      allow(Gitlab::CurrentSettings.current_application_settings).to receive_messages(
        max_number_of_repository_downloads: 10,
        max_number_of_repository_downloads_within_time_period: 600
      )

      Gitlab::ApplicationRateLimiter.throttled?(:unique_project_downloads_for_application,
        scope: { user: user }, resource: project, threshold: 10, interval: 600, peek: true)
      Gitlab::ApplicationRateLimiter.throttled?(:unique_project_downloads_for_application,
        scope: { user: user }, resource: project, threshold: 10, interval: 600)

      expected_key = "labkit:rl:{applimiter_unique_project_downloads_for_application" \
        ":limit_unique_project_downloads_by_user:user:#{user.id}}"
      members = Gitlab::Redis::RateLimiting.with { |r| r.smembers(expected_key) }

      expect(members).to contain_exactly(project.id.to_s)
    end

    it 'routes a set-mode namespace key with a user+namespace bucket' do
      user = build_stubbed(:user)
      namespace = build_stubbed(:group)
      project = build_stubbed(:project)

      Gitlab::ApplicationRateLimiter::LabkitAdapter.run!(:unique_project_downloads_for_namespace,
        scope: { user: user, namespace: namespace },
        context: { resource_id: project.id, threshold: 10, interval: 600 })

      expected_key = "labkit:rl:{applimiter_unique_project_downloads_for_namespace" \
        ":limit_unique_project_downloads_by_user_namespace" \
        ":user:#{user.id}:namespace:#{namespace.id}}"
      members = Gitlab::Redis::RateLimiting.with { |r| r.smembers(expected_key) }

      expect(members).to contain_exactly(project.id.to_s)
    end

    it 'lets the labkit adapter peek-dispatch an EE key with a Symbol :global scope' do
      Gitlab::ApplicationRateLimiter::LabkitAdapter.run!(:hard_phone_verification_transactions_limit,
        scope: { scope: :global })

      expect(
        Gitlab::ApplicationRateLimiter::LabkitAdapter.run_peek!(
          :hard_phone_verification_transactions_limit, scope: { scope: :global }
        )
      ).to be(false)

      expected_key = "labkit:rl:{applimiter_hard_phone_verification_transactions_limit" \
        ":limit_hard_phone_verification_transactions_by_scope:scope:global}"
      count = Gitlab::Redis::RateLimiting.with { |r| r.get(expected_key) }

      expect(count.to_i).to eq(1)
    end

    it 'counts phone verification transactions per dial code' do
      Gitlab::ApplicationRateLimiter::LabkitAdapter.run!(:dial_code_phone_verification_transactions_limit,
        scope: { international_dial_code: 44 }, context: { threshold: 10 })

      expected_key = "labkit:rl:{applimiter_dial_code_phone_verification_transactions_limit" \
        ":limit_phone_verification_transactions_by_dial_code:international_dial_code:44}"
      count = Gitlab::Redis::RateLimiting.with { |r| r.get(expected_key) }

      expect(count.to_i).to eq(1)
    end

    it 'counts phone verification transactions per card fingerprint' do
      Gitlab::ApplicationRateLimiter::LabkitAdapter.run!(:card_fingerprint_phone_verification_transactions_limit,
        scope: { stripe_card_fingerprint: 'card_fingerprint' })

      expected_key = "labkit:rl:{applimiter_card_fingerprint_phone_verification_transactions_limit" \
        ":limit_phone_verification_transactions_by_card_fingerprint:stripe_card_fingerprint:card_fingerprint}"
      count = Gitlab::Redis::RateLimiting.with { |r| r.get(expected_key) }

      expect(count.to_i).to eq(1)
    end

    it 'limits AI audit event ingest per user and per top-level namespace', :aggregate_failures do
      supported_rate_limits = Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits

      expect(supported_rate_limits.limit_for(:ai_duo_workflow_audit_event_ingest)).to eq(120)
      expect(supported_rate_limits.limit_for(:ai_audit_event_ingest_by_top_level_namespace)).to eq(20_000)
    end

    it 'counts AI audit events for a top-level namespace by the events in each request' do
      namespace = build_stubbed(:group)
      scope = { namespace: namespace }

      2.times do
        Gitlab::ApplicationRateLimiter.throttled?(:ai_audit_event_ingest_by_top_level_namespace, scope: scope,
          cost: 300)
      end

      expected_key = "labkit:rl:{applimiter_ai_audit_event_ingest_by_top_level_namespace" \
        ":limit_ai_audit_event_ingest_by_top_level_namespace:namespace:#{namespace.id}}"
      count = Gitlab::Redis::RateLimiting.with { |r| r.get(expected_key) }

      expect(count.to_f).to eq(600)
    end
  end
end
