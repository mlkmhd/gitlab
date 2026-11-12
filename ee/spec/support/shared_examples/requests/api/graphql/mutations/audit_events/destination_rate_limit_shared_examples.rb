# frozen_string_literal: true

# Requires `mutate`, `mutation_response` and `current_user`, with `mutate` set up to succeed.
RSpec.shared_examples 'a rate limited audit streaming destination mutation' do |model: AuditEvents::Group::ExternalStreamingDestination|
  context 'when the user is over the destination mutation rate limit' do
    before do
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?).and_call_original
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?)
        .with(anything, current_user, :audit_event_streaming_destination_mutation, scope: { user: current_user })
        .and_return(true)
    end

    it 'returns the rate limit error without writing', :aggregate_failures do
      expect(Gitlab::Audit::Auditor).not_to receive(:audit)

      expect { mutate }
        .not_to change { model.pluck(:id, :name, :active, :updated_at) }

      expect(mutation_response['errors']).to eq([Gitlab::ApplicationRateLimiter.throttled_error_message])
    end

    context 'when enforce_audit_streaming_destination_limits is disabled' do
      before do
        stub_feature_flags(enforce_audit_streaming_destination_limits: false)
      end

      it 'does not block the mutation but still runs the throttle check', :aggregate_failures do
        expect(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?)
          .with(anything, current_user, :audit_event_streaming_destination_mutation, scope: { user: current_user })
          .and_return(true)
        expect(Gitlab::Audit::Auditor).to receive(:audit).at_least(:once)

        mutate

        expect(mutation_response['errors']).to be_empty
      end
    end
  end
end
