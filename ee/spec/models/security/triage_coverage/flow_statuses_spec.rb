# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::TriageCoverage::FlowStatuses, feature_category: :security_asset_inventories do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:sast_fp_item) do
    create(:ai_catalog_item, :with_foundational_flow_reference, foundational_flow_reference: 'sast_fp_detection/v1',
      organization: organization)
  end

  let_it_be_with_reload(:root) do
    create(:group, organization: organization).tap do |g|
      g.namespace_settings.update!(duo_foundational_flows_enabled: true)
    end
  end

  let_it_be(:other_root) do
    create(:group, organization: organization).tap do |g|
      g.namespace_settings.update!(duo_foundational_flows_enabled: false)
    end
  end

  describe '.for_root_ids' do
    before do
      stub_licensed_features(ai_features: true, ai_workflows: true)
      root.sync_enabled_foundational_flows!([sast_fp_item.id])
    end

    it 'returns statuses per root group and trigger type', :aggregate_failures do
      result = described_class.for_root_ids([root.id, other_root.id])

      expect(result.keys).to contain_exactly(root.id, other_root.id)
      expect(result[root.id].keys).to match_array(Security::TriageCoverage::CapabilityBitmask.trigger_types)
      expect(result[root.id]).to include(
        sast_false_positive: :available,
        secret_detection_false_positive: :flow_not_enabled,
        vulnerability_enrichment: :not_applicable
      )
      expect(result[other_root.id][:sast_false_positive]).to eq(:foundational_flows_disabled)
    end
  end

  # `stub_licensed_features` would skip the SaaS plan lookup, so stub `License` instead.
  describe 'N+1 queries', :saas, :request_store do
    def ultimate_root
      create(:group_with_plan, plan: :ultimate_plan, organization: organization).tap do |g|
        g.namespace_settings.update!(duo_foundational_flows_enabled: true)
      end
    end

    before do
      stub_application_setting(check_namespace_plan: true)
      allow(License).to receive(:feature_available?).and_call_original
      allow(License).to receive(:feature_available?).with(:ai_workflows).and_return(true)
      allow(License).to receive(:feature_available?).with(:ai_features).and_return(true)
    end

    it 'does not add queries per root group with flows enabled', :aggregate_failures do
      one = [ultimate_root.id]
      three = Array.new(3) { ultimate_root.id }

      control = ActiveRecord::QueryRecorder.new { described_class.for_root_ids(one) }

      expect { described_class.for_root_ids(three) }.not_to exceed_query_limit(control)
      expect(described_class.for_root_ids(three).values.pluck(:sast_false_positive)).to all(eq(:flow_not_enabled))
    end
  end
end
