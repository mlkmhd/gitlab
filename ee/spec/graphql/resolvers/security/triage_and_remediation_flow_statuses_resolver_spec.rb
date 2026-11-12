# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Security::TriageAndRemediationFlowStatusesResolver, feature_category: :security_asset_inventories do
  include GraphqlHelpers

  let_it_be_with_reload(:root) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root) }
  let_it_be(:maintainer) { create(:user, maintainer_of: root) }
  let_it_be(:reporter) { create(:user, reporter_of: root) }

  let(:group) { subgroup }
  let(:current_user) { maintainer }

  subject(:resolved) do
    batch_sync { resolve(described_class, obj: group, ctx: { current_user: current_user }) }
  end

  before do
    stub_licensed_features(security_scan_profiles: true, ai_features: true, ai_workflows: true)
  end

  it 'returns one status per trigger type', :aggregate_failures do
    expect(resolved.pluck(:trigger_type))
      .to match_array(Security::TriageCoverage::CapabilityBitmask.trigger_types.map(&:to_s))
    expect(resolved.pluck(:flow_status)).to all(be_a(String))
  end

  it 'resolves the statuses of the root group', :aggregate_failures do
    root.namespace_settings.update!(duo_foundational_flows_enabled: false)

    expect(resolved).to include(
      {
        trigger_type: 'sast_false_positive',
        flow_status: 'foundational_flows_disabled',
        flow_name: Ai::Catalog::FoundationalFlow.sast_fp_detection_v1.translated_display_name
      },
      { trigger_type: 'vulnerability_enrichment', flow_status: 'not_applicable', flow_name: nil }
    )
  end

  context 'when the root group cannot be resolved' do
    before do
      allow(group).to receive(:traversal_ids).and_return([])
    end

    it 'returns the unresolved statuses instead of null' do
      expect(resolved).to include(
        {
          trigger_type: 'sast_false_positive',
          flow_status: 'flow_unavailable',
          flow_name: Ai::Catalog::FoundationalFlow.sast_fp_detection_v1.translated_display_name
        },
        { trigger_type: 'vulnerability_enrichment', flow_status: 'not_applicable', flow_name: nil }
      )
    end
  end

  context 'when the user cannot read security scan profiles' do
    let(:current_user) { reporter }

    it { is_expected.to be_nil }
  end
end
