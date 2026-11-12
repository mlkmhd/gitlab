# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.group.triageAndRemediationCoverageCounters', feature_category: :security_asset_inventories do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be_with_reload(:group) do
    create(:group).tap { |g| g.namespace_settings.update!(duo_foundational_flows_enabled: false) }
  end

  let_it_be(:enabled_project) { create(:project, namespace: group) }
  let_it_be(:auto_project) { create(:project, namespace: group) }
  let_it_be(:uncovered_project) { create(:project, namespace: group) }

  let_it_be(:enabled_filter) do
    create(:security_inventory_filters, project: enabled_project,
      triage_capabilities: { sast_false_positive: [true, false] })
  end

  let_it_be(:auto_filter) do
    create(:security_inventory_filters, project: auto_project,
      triage_capabilities: { sast_false_positive: [true, true] })
  end

  let_it_be(:uncovered_filter) { create(:security_inventory_filters, project: uncovered_project) }

  let_it_be(:enrichment_filter) do
    create(:security_inventory_filters, project: create(:project, namespace: group),
      triage_capabilities: { vulnerability_enrichment: [true, false] })
  end

  let(:query) do
    <<~GQL
      query($fullPath: ID!, $triggerType: ScanProfileTriggerType) {
        group(fullPath: $fullPath) {
          triageAndRemediationCoverageCounters(triggerType: $triggerType) {
            enabledCount
            autoCount
            flowMissingCount
          }
        }
      }
    GQL
  end

  let(:trigger_type) { 'SAST_FALSE_POSITIVE' }
  let(:variables) { { fullPath: group.full_path, triggerType: trigger_type } }
  let(:counters_data) { graphql_data_at(:group, :triage_and_remediation_coverage_counters) }

  subject(:execute_query) { post_graphql(query, current_user: current_user, variables: variables) }

  before do
    stub_licensed_features(security_scan_profiles: true)
  end

  context 'when the user does not have permission' do
    it 'returns null for the field' do
      execute_query

      expect(graphql_errors).to be_nil
      expect(counters_data).to be_nil
    end
  end

  context 'when the user has permission' do
    before_all do
      group.add_developer(current_user)
    end

    it 'returns the counts for the given trigger type', :aggregate_failures do
      execute_query

      expect(graphql_errors).to be_nil
      expect(counters_data).to eq('enabledCount' => 2, 'autoCount' => 1, 'flowMissingCount' => 2)
    end

    context 'without a trigger type' do
      let(:variables) { { fullPath: group.full_path } }

      it 'returns the counts for any trigger type, with no flow missing for a capability without a flow' do
        execute_query

        expect(counters_data).to eq('enabledCount' => 3, 'autoCount' => 1, 'flowMissingCount' => 2)
      end
    end

    context 'when the flow behind the trigger type is enabled' do
      let_it_be(:sast_fp_item) do
        create(:ai_catalog_item, :with_foundational_flow_reference,
          foundational_flow_reference: 'sast_fp_detection/v1', organization: group.organization)
      end

      before do
        stub_licensed_features(security_scan_profiles: true, ai_features: true, ai_workflows: true)
        group.namespace_settings.update!(duo_foundational_flows_enabled: true)
        group.sync_enabled_foundational_flows!([sast_fp_item.id])
      end

      it 'returns no flow missing count' do
        execute_query

        expect(counters_data).to eq('enabledCount' => 2, 'autoCount' => 1, 'flowMissingCount' => 0)
      end
    end

    context 'with several groups in one request' do
      let_it_be(:subgroup) { create(:group, parent: group) }
      let_it_be_with_reload(:other_group) { create(:group) }

      let_it_be(:sast_fp_item) do
        create(:ai_catalog_item, :with_foundational_flow_reference,
          foundational_flow_reference: 'sast_fp_detection/v1', organization: other_group.organization)
      end

      before_all do
        other_group.add_developer(current_user)
        create(:security_inventory_filters, project: create(:project, namespace: subgroup),
          triage_capabilities: { secret_detection_false_positive: [true, false] })
        create(:security_inventory_filters, project: create(:project, namespace: other_group),
          triage_capabilities: { sast_false_positive: [true, false] })
        create(:security_inventory_filters, project: create(:project, namespace: other_group),
          triage_capabilities: { secret_detection_false_positive: [true, false] })
      end

      before do
        stub_licensed_features(security_scan_profiles: true, ai_features: true, ai_workflows: true)
        other_group.namespace_settings.update!(duo_foundational_flows_enabled: true)
        other_group.sync_enabled_foundational_flows!([sast_fp_item.id])
      end

      def flow_missing_counts(*groups)
        fields = groups.each_with_index.map do |g, index|
          %(g#{index}: group(fullPath: "#{g.full_path}") { triageAndRemediationCoverageCounters { flowMissingCount } })
        end

        post_graphql("query { #{fields.join(' ')} }", current_user: current_user)

        groups.each_index.map do |index|
          graphql_data.dig("g#{index}", 'triageAndRemediationCoverageCounters', 'flowMissingCount')
        end
      end

      it 'resolves the missing flows once per request, from each group root', :aggregate_failures do
        allow(::Security::TriageCoverage::ProjectCapabilities).to receive(:missing_flows_masks).and_call_original

        expect(flow_missing_counts(group, subgroup, other_group)).to eq([3, 1, 1])
        expect(::Security::TriageCoverage::ProjectCapabilities).to have_received(:missing_flows_masks)
          .once.with(match_array([group.id, other_group.id]))
      end
    end

    # `read_group` authorizes traversing the parent `Group` type,
    # `read_security_scan_profiles` the `TriageAndRemediationCoverageCounters` type
    it_behaves_like 'authorizing granular token permissions for GraphQL',
      %i[read_group read_security_scan_profiles] do
      let(:user) { current_user }
      let(:boundary_object) { group }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }, variables: variables) }
    end

    context 'when the security_scan_profiles license is unavailable' do
      before do
        stub_licensed_features(security_scan_profiles: false)
      end

      it 'returns null for the field' do
        execute_query

        expect(graphql_errors).to be_nil
        expect(counters_data).to be_nil
      end
    end

    context 'with a trigger type that has no matching filters' do
      let(:trigger_type) { 'SAST_VULNERABILITY_RESOLUTION' }

      it 'returns zero counts', :aggregate_failures do
        execute_query

        expect(graphql_errors).to be_nil
        expect(counters_data).to eq('enabledCount' => 0, 'autoCount' => 0, 'flowMissingCount' => 0)
      end
    end

    context 'with a valid trigger type that has no triage bit' do
      let(:trigger_type) { 'DEFAULT_BRANCH_PIPELINE' }

      it 'returns null' do
        execute_query

        expect(graphql_errors).to be_nil
        expect(counters_data).to be_nil
      end
    end
  end
end
