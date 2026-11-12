# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Add denylist event type filters for an instance streaming destination', feature_category: :audit_events do
  include GraphqlHelpers

  let_it_be(:destination) { create(:audit_events_instance_external_streaming_destination) }

  let(:event_type_filters) { ['event_type_filters_created'] }
  let(:input) do
    {
      destination_id: global_id_of(destination).to_s,
      event_type_filters: event_type_filters
    }
  end

  let(:mutation) { graphql_mutation(:audit_events_instance_destination_denylist_events_add, input) }
  let(:mutation_response) { graphql_mutation_response(:audit_events_instance_destination_denylist_events_add) }

  subject(:mutate) { post_graphql_mutation(mutation, current_user: current_user) }

  context 'when feature is licensed' do
    before do
      stub_licensed_features(external_audit_events: true)
    end

    context 'when current user is an instance admin', :enable_admin_mode do
      let_it_be(:current_user) { create(:admin) }

      it 'creates a denylist filter' do
        expect { mutate }.to change { destination.event_type_denylist_filters.count }.by(1)

        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['eventTypeFilters']).to contain_exactly('event_type_filters_created')
      end

      context 'when an event_type_filters argument is empty' do
        let(:event_type_filters) { [] }

        it 'returns an error' do
          mutate

          expect(graphql_errors.first['message']).to include('event type filters must be present')
        end
      end

      context 'when more event types are passed than the maximum' do
        let(:event_type_filters) { Array.new(Types::BaseArgument::MAX_ARRAY_SIZE + 1) { |i| "event_type_#{i}" } }

        it 'returns an error and does not create denylist filters' do
          expect { mutate }.not_to change { destination.event_type_denylist_filters.count }

          expect(graphql_errors.first['message']).to include('eventTypeFilters is too long')
        end
      end

      context 'when the event type is already on the allowlist' do
        before do
          create(:audit_events_instance_event_type_filters,
            external_streaming_destination: destination,
            audit_event_type: 'event_type_filters_created')
        end

        it 'returns an error and does not create a denylist filter' do
          expect { mutate }.not_to change { destination.event_type_denylist_filters.count }

          expect(mutation_response['errors']).to include(a_string_including('already on the allowlist'))
          expect(mutation_response['eventTypeFilters']).to be_empty
        end
      end
    end

    context 'when current user is not an instance admin' do
      let_it_be(:current_user) { create(:user) }

      it_behaves_like 'a mutation on an unauthorized resource'
    end
  end

  context 'when feature is unlicensed', :enable_admin_mode do
    let_it_be(:current_user) { create(:admin) }

    before do
      stub_licensed_features(external_audit_events: false)
    end

    it_behaves_like 'a mutation on an unauthorized resource'
  end

  context 'with granular token authorization' do
    let_it_be(:granular_token_user) { create(:admin) }

    before do
      stub_licensed_features(external_audit_events: true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_audit_event_streaming_destination do
      let(:user) { granular_token_user }
      let(:boundary_object) { :instance }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
