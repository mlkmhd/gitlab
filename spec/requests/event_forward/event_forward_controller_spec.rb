# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EventForward::EventForwardController, feature_category: :product_analytics do
  let(:tracker) { instance_double(Gitlab::Tracking::Destinations::Snowplow) }
  let(:event_eligibility_checker) { instance_double(Gitlab::Tracking::EventEligibilityChecker) }
  let(:logger) { instance_double(Logger) }
  let(:event_1) { { 'se_ac' => 'event_1', 'aid' => 'app_id_1' } }
  let(:event_2) { { 'se_ac' => 'event_2', 'aid' => 'app_id_2' } }
  let(:payload) do
    {
      'data' => [
        event_1,
        event_2
      ]
    }
  end

  before do
    allow(Gitlab::Tracking).to receive(:tracker).and_return(tracker)
    allow(tracker).to receive_messages(emit_event_payload: nil, hostname: 'localhost')
    allow(Gitlab::Tracking::EventEligibilityChecker).to receive(:new).and_return(event_eligibility_checker)
    allow(event_eligibility_checker).to receive(:eligible?).and_return(true)
    allow(EventForward::Logger).to receive(:build).and_return(logger)
    allow(logger).to receive(:info)
  end

  describe 'POST #forward' do
    let(:editor_telemetry_header) { { 'X-GitLab-Editor-Telemetry' => '1' } }
    let(:request) { post event_forwarding_path, params: payload, as: :json }

    context 'when the payload is more than 10 megabytes' do
      let(:event_2) { { 'se_ac' => 'a' * 11_000_000, 'aid' => 'app_id_2' } }

      it 'responds with 400 bad request' do
        expect(tracker).not_to receive(:emit_event_payload)

        request

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when instance type is self-managed' do
      it 'forwards each event to the Snowplow tracker with updated app_id' do
        payload['data'].each do |event|
          expected_event = event.merge('aid' => "#{event['aid']}_sm")

          expect(tracker).to receive(:emit_event_payload).with(expected_event)
        end

        request
      end
    end

    it 'logs the number of enqueued events' do
      expect(logger).to receive(:info).with("Enqueued events for forwarding. Count: #{payload['data'].size}")

      request
    end

    it 'returns successful response' do
      request

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to be_empty
    end

    context 'when filtering events by eligibility' do
      before do
        allow(event_eligibility_checker).to receive(:eligible?).with("event_1", "app_id_1").and_return(true)
        allow(event_eligibility_checker).to receive(:eligible?).with("event_2", "app_id_2").and_return(false)
      end

      it 'forwards only eligible events to the Snowplow tracker with updated app_id' do
        expected_event = event_1.merge('aid' => 'app_id_1_sm')

        expect(tracker).to receive(:emit_event_payload).with(expected_event)
        expect(tracker).not_to receive(:emit_event_payload).with(event_2)

        request
      end

      it 'logs only the number of eligible events' do
        expect(logger).to receive(:info).with("Enqueued events for forwarding. Count: 1")

        request
      end
    end

    context 'when all events are ineligible' do
      before do
        allow(event_eligibility_checker).to receive(:eligible?).and_return(false)
      end

      it 'does not forward any events to the Snowplow tracker' do
        payload['data'].each do |event|
          expect(tracker).not_to receive(:emit_event_payload).with(event)
        end

        request
      end

      it 'logs zero enqueued events' do
        expect(logger).to receive(:info).with("Enqueued events for forwarding. Count: 0")

        request
      end
    end

    context 'when events have no app_id' do
      let(:event_1) { { 'se_ac' => 'event_1' } }
      let(:event_2) { { 'se_ac' => 'event_2' } }

      it 'forwards each event to the Snowplow tracker' do
        payload['data'].each do |event|
          expect(tracker).to receive(:emit_event_payload).with(event)
        end

        request
      end
    end

    context 'when app_id already has the suffix' do
      let(:event_1) { { 'se_ac' => 'event_1', 'aid' => 'app_id_sm' } }
      let(:event_2) { { 'se_ac' => 'event_2', 'aid' => 'app_id_sm' } }

      it 'forwards each event to the Snowplow tracker' do
        payload['data'].each do |event|
          expect(tracker).to receive(:emit_event_payload).with(event)
        end

        request
      end
    end

    context 'when X-GitLab-Editor-Telemetry header is present' do
      let(:request) { post event_forwarding_path, params: payload, as: :json, headers: editor_telemetry_header }

      context 'when unauthenticated' do
        it 'injects gitlab_standard context with null user identity' do
          expect(tracker).to receive(:emit_event_payload).at_least(:once) do |event|
            cx = Gitlab::Json.safe_parse(Base64.decode64(event['cx']))
            standard = cx['data'].find do |c|
              c['schema'] == Gitlab::Tracking::StandardContext::GITLAB_STANDARD_SCHEMA_URL
            end

            expect(standard).not_to be_nil
            expect(standard['data']['user_id']).to be_nil
            expect(standard['data']['global_user_id']).to be_nil
          end

          request
        end
      end

      context 'when authenticated with a personal access token' do
        let(:user) { create(:user) }
        let(:pat) { create(:personal_access_token, user: user) }
        let(:request) do
          post event_forwarding_path, params: payload, as: :json,
            headers: editor_telemetry_header.merge('Private-Token' => pat.token)
        end

        it 'injects gitlab_standard context with user identity populated' do
          expect(tracker).to receive(:emit_event_payload).at_least(:once) do |event|
            cx = Gitlab::Json.safe_parse(Base64.decode64(event['cx']))
            standard = cx['data'].find do |c|
              c['schema'] == Gitlab::Tracking::StandardContext::GITLAB_STANDARD_SCHEMA_URL
            end

            expect(standard['data']['user_id']).not_to be_nil
            expect(standard['data']['global_user_id']).not_to be_nil
          end

          request
        end
      end

      context 'when authenticated with a granular personal access token' do
        let(:user) { create(:user) }
        let(:request) do
          post event_forwarding_path, params: payload, as: :json,
            headers: editor_telemetry_header.merge('Private-Token' => pat.token)
        end

        context 'with the editor telemetry permission' do
          let(:pat) do
            create(:granular_pat, user: user,
              boundary: Authz::Boundary.for(::Authz::GranularScope::Access::USER),
              permissions: :create_editor_telemetry)
          end

          it 'forwards the events and returns ok' do
            expect(tracker).to receive(:emit_event_payload).at_least(:once)

            request

            expect(response).to have_gitlab_http_status(:ok)
          end
        end

        context 'without the editor telemetry permission' do
          let(:pat) { create(:granular_pat, user: user) }

          it 'responds with 403 forbidden and does not forward events' do
            expect(tracker).not_to receive(:emit_event_payload)

            request

            expect(response).to have_gitlab_http_status(:forbidden)
          end
        end
      end

      context 'when authenticated with an OAuth token' do
        let(:user) { create(:user) }
        let(:oauth_token) { create(:oauth_access_token, resource_owner: user) }
        let(:request) do
          post event_forwarding_path, params: payload, as: :json,
            headers: editor_telemetry_header.merge('Authorization' => "Bearer #{oauth_token.plaintext_token}")
        end

        it 'injects gitlab_standard context with user identity populated' do
          expect(tracker).to receive(:emit_event_payload).at_least(:once) do |event|
            cx = Gitlab::Json.safe_parse(Base64.decode64(event['cx']))
            standard = cx['data'].find do |c|
              c['schema'] == Gitlab::Tracking::StandardContext::GITLAB_STANDARD_SCHEMA_URL
            end

            expect(standard['data']['user_id']).not_to be_nil
            expect(standard['data']['global_user_id']).not_to be_nil
          end

          request
        end
      end

      context 'when event already has a gitlab_standard context of the current version' do
        let(:client_identity) { { 'user_id' => 1, 'global_user_id' => 'client-supplied' } }
        let(:existing_standard_cx) do
          Base64.strict_encode64(Gitlab::Json.dump(
            'schema' => 'iglu:com.snowplowanalytics.snowplow/contexts/jsonschema/1-0-1',
            'data' => [
              { 'schema' => Gitlab::Tracking::StandardContext::GITLAB_STANDARD_SCHEMA_URL, 'data' => client_identity }
            ]
          ))
        end

        let(:event_1) { { 'se_ac' => 'event_1', 'aid' => 'app_id_1', 'cx' => existing_standard_cx } }

        it 'replaces it with the server context, so the client cannot supply its own identity' do
          payload['data'] = [event_1]

          expect(tracker).to receive(:emit_event_payload).once do |event|
            cx = Gitlab::Json.safe_parse(Base64.decode64(event['cx']))

            expect(cx['data']).to contain_exactly(hash_including(
              'schema' => Gitlab::Tracking::StandardContext::GITLAB_STANDARD_SCHEMA_URL,
              'data' => hash_including('user_id' => nil, 'global_user_id' => nil)
            ))
          end

          request
        end
      end

      context 'when event cx cannot be read' do
        using RSpec::Parameterized::TableSyntax

        where(:case_name, :cx) do
          'invalid base64'                        | 'not base64!'
          'invalid JSON'                          | Base64.strict_encode64('not valid json {{{')
          'JSON without a context list'           | Base64.strict_encode64('[]')
          'a number instead of a string'          | 12345
          'a context that is not an object'       | Base64.strict_encode64('{"data":[1]}')
          'a context whose data is not an object' | Base64.strict_encode64('{"data":[{"schema":"x","data":"y"}]}')
        end

        with_them do
          let(:event_1) { { 'se_ac' => 'event_1', 'aid' => 'app_id_1', 'cx' => cx } }

          it 'forwards the event with its cx unchanged' do
            payload['data'] = [event_1]

            expect(tracker).to receive(:emit_event_payload).with(hash_including('cx' => cx))

            request

            expect(response).to have_gitlab_http_status(:ok)
          end
        end
      end

      context 'when event cx holds client contexts' do
        using RSpec::Parameterized::TableSyntax

        # A run of '?' encodes to '_' in URL-safe base64 and to '/' in standard base64.
        let(:client_extra) { { 'timestamp' => '1794098835061', 'label' => '????????' } }
        let(:client_standard_context) do
          {
            'schema' => 'iglu:com.gitlab/gitlab_standard/jsonschema/1-1-1',
            'data' => { 'source' => 'gl-visual-studio-extension', 'user_id' => 1234567, 'extra' => client_extra }
          }
        end

        let(:ide_context) do
          {
            'schema' => 'iglu:com.gitlab/ide_extension_version/jsonschema/1-1-0',
            'data' => { 'ide_name' => 'Microsoft Visual Studio', 'extension_name' => 'gl-visual-studio-extension' }
          }
        end

        let(:client_cx) do
          json = Gitlab::Json.dump(
            'schema' => 'iglu:com.snowplowanalytics.snowplow/contexts/jsonschema/1-0-1',
            'data' => [client_standard_context, ide_context]
          )

          urlsafe ? Base64.urlsafe_encode64(json, padding: false) : Base64.strict_encode64(json)
        end

        let(:event_1) { { 'se_ac' => 'event_1', 'aid' => 'app_id_1', 'cx' => client_cx } }

        before do
          payload['data'] = [event_1]
        end

        # Snowplow trackers, such as @snowplow/tracker-core, write URL-safe base64 without padding.
        where(:case_name, :urlsafe) do
          'URL-safe without padding' | true
          'standard with padding'    | false
        end

        with_them do
          it 'keeps the client contexts' do
            expect(tracker).to receive(:emit_event_payload).once do |event|
              cx = Gitlab::Json.safe_parse(Base64.decode64(event['cx']))

              expect(cx['data']).to include(ide_context)
            end

            request
          end

          it 'replaces the client gitlab_standard context with the server one, keeping its source and extra' do
            expect(tracker).to receive(:emit_event_payload).once do |event|
              cx = Gitlab::Json.safe_parse(Base64.decode64(event['cx']))
              standard_contexts = cx['data'].select { |c| c['schema'].include?('/gitlab_standard/') }

              expect(standard_contexts).to contain_exactly(hash_including(
                'schema' => Gitlab::Tracking::StandardContext::GITLAB_STANDARD_SCHEMA_URL,
                'data' => hash_including(
                  'source' => 'gl-visual-studio-extension', 'user_id' => nil, 'extra' => client_extra
                )
              ))
            end

            request
          end
        end
      end

      context 'when event has existing cx without gitlab_standard' do
        let(:other_context) { { 'schema' => 'iglu:com.example/test/jsonschema/1-0-0', 'data' => { 'key' => 'value' } } }
        let(:existing_cx) do
          Base64.strict_encode64(Gitlab::Json.dump(
            'schema' => 'iglu:com.snowplowanalytics.snowplow/contexts/jsonschema/1-0-0',
            'data' => [other_context]
          ))
        end

        let(:event_1) { { 'se_ac' => 'event_1', 'aid' => 'app_id_1', 'cx' => existing_cx } }

        it 'preserves existing contexts and appends gitlab_standard' do
          payload['data'] = [event_1]

          expect(tracker).to receive(:emit_event_payload).once do |event|
            cx = Gitlab::Json.safe_parse(Base64.decode64(event['cx']))

            expect(cx['data']).to include(hash_including('schema' => other_context['schema']))
            expect(cx['data']).to include(hash_including(
              'schema' => Gitlab::Tracking::StandardContext::GITLAB_STANDARD_SCHEMA_URL)
                                         )
          end

          request
        end
      end
    end

    describe 'context validation' do
      let(:validator) { instance_double(Gitlab::Tracking::Destinations::SnowplowContextValidator) }
      # A run of '?' encodes to '_' in URL-safe base64, as Snowplow trackers write it.
      let(:context_data) { [{ 'schema' => 'iglu:com.gitlab/test/jsonschema/1-0-0', 'data' => { 'key' => '?????' } }] }
      let(:encoded_context) { Base64.urlsafe_encode64({ 'data' => context_data }.to_json, padding: false) }
      let(:event_with_context) { { 'se_ac' => 'event_1', 'aid' => 'app_id_1', 'cx' => encoded_context } }

      before do
        allow(Gitlab::Tracking::Destinations::SnowplowContextValidator).to receive(:new).and_return(validator)
        allow(validator).to receive(:validate!)
        payload['data'] = [event_with_context]
      end

      context 'when in development environment' do
        before do
          allow(Rails.env).to receive(:development?).and_return(true)
        end

        it 'validates the context' do
          expect(validator).to receive(:validate!).with(context_data)

          request
        end

        context 'when validation fails' do
          before do
            allow(validator).to receive(:validate!).and_raise(ArgumentError)
          end

          it 'payload still sent to the emitter' do
            expect(tracker).to receive(:emit_event_payload)

            suppress(ArgumentError) { request }
          end
        end
      end

      context 'when not in development environment' do
        before do
          allow(Rails.env).to receive(:development?).and_return(false)
        end

        it 'does not validate the context' do
          expect(validator).not_to receive(:validate!)

          request
        end
      end

      context 'when event does not have cx field' do
        before do
          allow(Rails.env).to receive(:development?).and_return(true)
          payload['data'] = [event_1]
        end

        it 'does not validate the context' do
          expect(validator).not_to receive(:validate!)

          request
        end
      end
    end
  end

  describe 'session persistence' do
    # Asserted through the request options rather than a Set-Cookie or Redis side effect: an
    # unchanged session is also left alone by write throttling, so an observable effect would
    # not distinguish the two. Telemetry beacons must not refresh the session, or a page
    # pinging on a heartbeat would keep it alive and defeat inactivity-based session expiry.
    it 'forwards events without committing (extending) the session', :aggregate_failures do
      post event_forwarding_path, params: payload, as: :json

      expect(response).to have_gitlab_http_status(:ok)
      expect(request.session_options[:skip]).to be(true)
    end
  end
end
