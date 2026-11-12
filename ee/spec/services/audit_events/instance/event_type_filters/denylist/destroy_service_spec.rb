# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Instance::EventTypeFilters::Denylist::DestroyService, feature_category: :audit_events do
  let_it_be(:user) { create(:user) }
  let_it_be(:destination) { create(:audit_events_instance_external_streaming_destination) }
  let_it_be(:event_type_filters) { ['event_type_filters_created'] }

  before do
    create(:audit_events_instance_event_type_filters,
      external_streaming_destination: destination,
      audit_event_type: 'event_type_filters_created',
      kind: :deny)
  end

  subject(:response) do
    described_class.new(
      destination: destination,
      event_type_filters: event_type_filters,
      current_user: user
    ).execute
  end

  describe '#execute' do
    it 'removes the denylist filter and emits an instance audit event', :aggregate_failures do
      expect { response }
        .to change { destination.event_type_denylist_filters.count }.by(-1)
        .and change { AuditEvents::InstanceAuditEvent.count }.by(1)

      expect(response).to be_success
    end

    context 'when the filter does not exist' do
      let_it_be(:event_type_filters) { ['nonexistent_filter'] }

      it 'returns an error and does not delete anything' do
        expect { response }.not_to change { destination.event_type_denylist_filters.count }
        expect(response).to be_error
        expect(response.message).to include('nonexistent_filter')
      end
    end

    context 'when the event type exists only on the allowlist' do
      let_it_be(:destination) { create(:audit_events_instance_external_streaming_destination) }
      let_it_be(:allow_filter) do
        create(:audit_events_instance_event_type_filters,
          external_streaming_destination: destination,
          audit_event_type: 'event_type_filters_deleted')
      end

      let_it_be(:event_type_filters) { ['event_type_filters_deleted'] }

      it 'returns an error and keeps the allowlist entry' do
        expect(response).to be_error
        expect(response.message).to include('event_type_filters_deleted')
        expect(allow_filter.reload).to be_allow
      end
    end

    context 'when some filters exist on the denylist and some do not' do
      let_it_be(:event_type_filters) { %w[event_type_filters_created nonexistent_filter] }

      it 'returns an error, does not delete any filters, and does not emit an audit event', :aggregate_failures do
        expect { response }
          .to not_change { destination.event_type_denylist_filters.count }
          .and not_change { AuditEvents::InstanceAuditEvent.count }

        expect(response).to be_error
        expect(response.message).to include('nonexistent_filter')
        expect(response.message).not_to include('event_type_filters_created')
      end
    end
  end
end
