# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Security metrics through ProjectQuery', :elastic_delete_by_query, :sidekiq_inline, feature_category: :vulnerability_management do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:current_user) { create(:user, maintainer_of: project) }
  let_it_be(:remediated_week) { Time.current.utc.beginning_of_week(:monday) - 1.week }

  let_it_be(:vulnerability) do
    create(:vulnerability, :with_finding, :resolved, severity: :critical, report_type: :sast, project: project,
      detected_at: remediated_week - 2.days, resolved_at: remediated_week + 1.day)
  end

  let(:query) do
    graphql_query_for('project', { 'fullPath' => project.full_path }, <<~FIELDS)
      securityMetrics {
        __typename
        mttrOverTime(startDate: "#{remediated_week.to_date.iso8601}", endDate: "#{Date.current.iso8601}") {
          startDate endDate count sumDays mttr
          bySeverity { severity count sumDays mttr }
          byReportType { reportType count sumDays mttr }
        }
      }
    FIELDS
  end

  let(:security_metrics_data) { graphql_data_at(:project, :security_metrics) }
  let(:mttr_over_time_data) { security_metrics_data['mttrOverTime'] }

  before do
    stub_licensed_features(security_dashboard: true)
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
    Elastic::ProcessBookkeepingService.track!(vulnerability)
    ensure_elasticsearch_index!
  end

  describe 'mttrOverTime' do
    let(:mttr_chart_enabled) { true }

    before do
      stub_feature_flags(security_dashboard_mttr_chart: mttr_chart_enabled)
      post_graphql(query, current_user: current_user)
    end

    it_behaves_like 'a working graphql query'

    it_behaves_like 'a dense mttrOverTime response'

    context 'when the security_dashboard_mttr_chart feature flag is disabled' do
      let(:mttr_chart_enabled) { false }

      it 'returns null for mttrOverTime and keeps the rest of securityMetrics' do
        expect(graphql_errors).to be_nil
        expect(security_metrics_data).to eq('__typename' => 'SecurityMetrics', 'mttrOverTime' => nil)
      end
    end
  end

  describe 'with a fine-grained personal access token' do
    let_it_be(:vulnerability_read) do
      create(:vulnerability_read, project: project, severity: :high, report_type: :sast, identifier_names: ['CWE-79'])
    end

    let(:metrics_query) do
      graphql_query_for('project', { 'fullPath' => project.full_path }, <<~FIELDS)
        securityMetrics {
          vulnerabilitiesPerSeverity { high { count } }
          vulnerabilitiesOverTime(startDate: "#{1.week.ago.to_date.iso8601}", endDate: "#{Date.current.iso8601}") {
            nodes { date bySeverity { severity count } byReportType { reportType count } }
          }
          vulnerabilitiesByAge { name bySeverity { severity count } byReportType { reportType count } }
          vulnerabilitiesByIdentifier { name count bySeverity { severity count } }
        }
      FIELDS
    end

    let(:user) { current_user }
    let(:boundary_object) { project }
    let(:request) { post_graphql(metrics_query, token: { personal_access_token: pat }) }

    before do
      Elastic::ProcessBookkeepingService.track!(vulnerability_read)
      ensure_elasticsearch_index!
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_vulnerability, :read_project]

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      [:read_vulnerability, :read_project] do
      let(:skipped_data_path) { %i[project security_metrics vulnerabilities_per_severity high] }
    end

    it_behaves_like 'denying a granular token that only authorizes the parent of a field', :read_project do
      let(:parent_data_path) { %i[project] }
      let(:field_data_path) { %i[project security_metrics] }
    end

    it 'returns the metrics that a legacy token gets', :aggregate_failures do
      post_graphql(metrics_query, current_user: current_user)
      legacy_metrics = graphql_data_at(:project, :security_metrics)

      granular_token = create(:granular_pat, user: current_user, boundary: ::Authz::Boundary.for(project),
        permissions: %w[read_vulnerability read_project])
      post_graphql(metrics_query, token: { personal_access_token: granular_token })

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:project, :security_metrics)).to eq(legacy_metrics)

      high = a_collection_including(a_hash_including('severity' => 'HIGH', 'count' => 1))
      sast = a_collection_including(a_hash_including('reportType' => 'SAST', 'count' => 1))
      expect(legacy_metrics.dig('vulnerabilitiesPerSeverity', 'high')).to eq('count' => 1)
      expect(legacy_metrics.dig('vulnerabilitiesOverTime', 'nodes'))
        .to include(a_hash_including('bySeverity' => high, 'byReportType' => sast))
      expect(legacy_metrics['vulnerabilitiesByAge'])
        .to include(a_hash_including('bySeverity' => high, 'byReportType' => sast))
      expect(legacy_metrics['vulnerabilitiesByIdentifier'])
        .to include(a_hash_including('name' => 'CWE-79', 'bySeverity' => high))
    end

    # Any fine-grained token reads a public project, as an anonymous user can, so there
    # Vulnerability: Read is the only token permission in front of the metrics.
    context 'when the project is public' do
      let_it_be(:public_project) { create(:project, :public, developers: current_user) }

      it 'does not return the metrics to a token without permissions' do
        granular_token = create(:granular_pat, user: current_user, boundary: ::Authz::Boundary.for(public_project))
        post_graphql(
          graphql_query_for('project', { 'fullPath' => public_project.full_path }, 'securityMetrics { __typename }'),
          token: { personal_access_token: granular_token }
        )

        expect(graphql_errors).to be_nil
        expect(graphql_data_at(:project)).to be_present
        expect(graphql_data_at(:project, :security_metrics)).to be_nil
      end
    end
  end
end
