# frozen_string_literal: true

# Ai::FlowTrigger rejects the scheduled event type unless experiment and beta features
# are on, and the instance setting defaults to false.
RSpec.shared_context 'with scheduled triggers available' do
  before do
    stub_application_setting(instance_level_ai_beta_features_enabled: true)
  end
end
