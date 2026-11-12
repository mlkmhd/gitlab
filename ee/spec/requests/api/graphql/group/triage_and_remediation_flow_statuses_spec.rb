# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying a group\'s triage and remediation flow statuses', feature_category: :security_asset_inventories do
  include GraphqlHelpers

  let_it_be_with_reload(:root) { create(:group) }
  let_it_be(:organization) { root.organization }
  let_it_be(:subgroup) { create(:group, parent: root) }
  let_it_be(:maintainer) { create(:user, maintainer_of: root) }
  let_it_be(:reporter) { create(:user, reporter_of: root) }
  let_it_be(:sast_fp_item) do
    create(:ai_catalog_item, :with_foundational_flow_reference, foundational_flow_reference: 'sast_fp_detection/v1',
      organization: organization)
  end

  let(:group) { root }
  let(:query) do
    graphql_query_for(:group, { full_path: group.full_path },
      query_graphql_field(:triage_and_remediation_flow_statuses, {}, 'triggerType flowStatus flowName'))
  end

  let(:statuses) do
    graphql_data_at(:group, :triage_and_remediation_flow_statuses).to_h { |s| [s['triggerType'], s['flowStatus']] }
  end

  let(:flow_names) do
    graphql_data_at(:group, :triage_and_remediation_flow_statuses).to_h { |s| [s['triggerType'], s['flowName']] }
  end

  before do
    stub_licensed_features(security_scan_profiles: true, ai_features: true, ai_workflows: true)
  end

  context 'when foundational flows are enabled and one flow is turned on' do
    before do
      root.namespace_settings.update!(duo_foundational_flows_enabled: true)
      root.sync_enabled_foundational_flows!([sast_fp_item.id])
    end

    it 'returns a status for every trigger type', :aggregate_failures do
      post_graphql(query, current_user: maintainer)

      expect(graphql_errors).to be_nil
      expect(statuses).to eq(
        'SBOM_INGESTED' => 'FLOW_UNAVAILABLE',
        'SAST_FALSE_POSITIVE' => 'AVAILABLE',
        'SAST_VULNERABILITY_RESOLUTION' => 'FLOW_NOT_ENABLED',
        'SECRET_DETECTION_FALSE_POSITIVE' => 'FLOW_NOT_ENABLED',
        'VULNERABILITY_ENRICHMENT' => 'NOT_APPLICABLE'
      )
      expect(flow_names).to eq(
        'SBOM_INGESTED' => Ai::Catalog::FoundationalFlow.resolve_dependency_bump_experimental.translated_display_name,
        'SAST_FALSE_POSITIVE' => Ai::Catalog::FoundationalFlow.sast_fp_detection_v1.translated_display_name,
        'SAST_VULNERABILITY_RESOLUTION' =>
          Ai::Catalog::FoundationalFlow.resolve_sast_vulnerability_v1.translated_display_name,
        'SECRET_DETECTION_FALSE_POSITIVE' =>
          Ai::Catalog::FoundationalFlow.secrets_fp_detection_v1.translated_display_name,
        'VULNERABILITY_ENRICHMENT' => nil
      )
      expect(flow_names.except('VULNERABILITY_ENRICHMENT').values).to all(be_present)
    end

    context 'when querying a subgroup' do
      let(:group) { subgroup }

      it 'resolves the statuses from the root group' do
        post_graphql(query, current_user: maintainer)

        expect(statuses).to include('SAST_FALSE_POSITIVE' => 'AVAILABLE')
      end
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL',
    %i[read_group read_security_scan_profiles] do
    let(:user) { maintainer }
    let(:boundary_object) { root }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
  end

  context 'when a granular token only has the group read permission' do
    let_it_be(:read_group) { ::Authz::PermissionGroups::Assignable.preferred_for_permission(:read_group).name }
    let_it_be(:pat) do
      create(:granular_pat, user: maintainer, boundary: ::Authz::Boundary.for(root), permissions: [read_group])
    end

    it 'does not return the statuses', :aggregate_failures do
      post_graphql(query, token: { personal_access_token: pat })

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:group, :triage_and_remediation_flow_statuses)).to be_nil
    end
  end

  it 'adds no queries per group beyond authorization' do
    create_list(:group, 2, maintainers: maintainer)
    multi_query = graphql_query_for(:groups, {},
      query_graphql_field(:nodes, {},
        query_graphql_field(:triage_and_remediation_flow_statuses, {}, 'triggerType flowStatus flowName')))

    post_graphql(multi_query, current_user: maintainer)
    control = ActiveRecord::QueryRecorder.new { post_graphql(multi_query, current_user: maintainer) }
    create(:group, maintainers: maintainer)

    # The single allowed query is the per-group membership lookup done by authorization.
    expect { post_graphql(multi_query, current_user: maintainer) }.not_to exceed_query_limit(control).with_threshold(1)
  end

  context 'when foundational flows are disabled' do
    before do
      root.namespace_settings.update!(duo_foundational_flows_enabled: false)
    end

    it 'reports them as disabled' do
      post_graphql(query, current_user: maintainer)

      expect(statuses).to include(
        'SAST_FALSE_POSITIVE' => 'FOUNDATIONAL_FLOWS_DISABLED', 'VULNERABILITY_ENRICHMENT' => 'NOT_APPLICABLE')
    end
  end

  context 'when the user cannot read security scan profiles' do
    it 'returns null for the field', :aggregate_failures do
      post_graphql(query, current_user: reporter)

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:group)).to include('triageAndRemediationFlowStatuses' => nil)
    end
  end

  context 'when the group is not licensed for security scan profiles' do
    before do
      stub_licensed_features(security_scan_profiles: false)
    end

    it 'returns null for the field' do
      post_graphql(query, current_user: maintainer)

      expect(graphql_data_at(:group)).to include('triageAndRemediationFlowStatuses' => nil)
    end
  end
end
