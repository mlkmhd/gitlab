# frozen_string_literal: true

# On Self-Managed, the default deployment in specs, the bl_security flow (and with it agentic analyzer
# ingestion) also needs the instance beta setting and GitLab's per-instance enablement.
# Override `bl_security_enabled_for_instance` to turn the enablement off.
RSpec.shared_context 'with bl_security enabled for the instance' do
  let(:bl_security_enabled_for_instance) { true }

  before do
    stub_application_setting(instance_level_ai_beta_features_enabled: true)
    allow(Ai::Catalog::FoundationalFlows::EnabledFlowsClient).to receive(:enabled?)
      .with('bl_security').and_return(bl_security_enabled_for_instance)
  end
end
