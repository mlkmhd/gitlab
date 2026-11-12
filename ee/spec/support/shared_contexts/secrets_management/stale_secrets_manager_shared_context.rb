# frozen_string_literal: true

# A lagging replica still reads `provisioning` right after the Sidekiq activation.
# Include after the row is active on the primary; needs `secrets_manager`.
RSpec.shared_context 'with a secrets manager read from a replica that has not replayed the activation' do
  before do
    stale = secrets_manager.class.find(secrets_manager.id)
    stale.status = secrets_manager.class::STATUSES[:provisioning]

    allow(secrets_manager.public_send(secrets_manager.scope_name)).to receive(:secrets_manager).and_return(stale)
    allow(secrets_manager.class.load_balancer).to receive(:primary_only?).and_return(false)
  end
end
