# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Compliance::Anthropic::Transcripts::SyncPageService, feature_category: :ai_governance do
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:integration) { create(:ai_compliance_anthropic_integration, namespace: group, enabled: true) }
  let_it_be(:session_xid) { 'clls_01HxKpLmNoPqRsTuVwXyZaBc' }
  let_it_be_with_reload(:governance_session) do
    create(:ai_governance_session, :external, namespace: group, user: user, external_xid: session_xid,
      session_started_at: Time.utc(2026, 7, 1, 9))
  end

  let(:messages_url) { "https://api.anthropic.com/v1/compliance/apps/sessions/local/#{session_xid}/messages" }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:envelope) { { id: session_xid, created_at: '2026-07-01T09:00:00Z', user: { id: 'user_01ZYXWVU' } } }

  def message(id, created_at = '2026-07-01T10:00:00Z')
    { id: id, role: 'user', created_at: created_at, content: [{ type: 'text', text: "text of #{id}" }] }
  end

  def stub_messages(page: nil, data: [], next_page: nil, session: envelope)
    query = { 'order' => 'desc', 'limit' => described_class::MESSAGES_PER_PAGE.to_s, 'page' => page }.compact

    stub_request(:get, messages_url).with(query: query).to_return(
      status: 200, headers: json_headers,
      body: { session: session, data: data, next_page: next_page }.to_json
    )
  end

  def stub_expired_cursor(page)
    query = { 'order' => 'desc', 'limit' => described_class::MESSAGES_PER_PAGE.to_s, 'page' => page }.compact
    body = { error: { type: 'invalid_request_error', message: 'The page cursor has expired. Restart the walk.' } }

    stub_request(:get, messages_url).with(query: query)
      .to_return(status: 400, headers: json_headers, body: body.to_json)
  end

  def stub_session_not_found(query = hash_including({}))
    stub_request(:get, messages_url).with(query: query).to_return(
      status: 404, headers: json_headers,
      body: { error: { type: 'not_found_error', message: 'Local session not found' } }.to_json
    )
  end

  def walk_state
    Ai::Compliance::Anthropic::Session.find_by(ai_governance_session_id: governance_session.id)
  end

  def execute(params = {})
    described_class.new(integration, governance_session, params).execute
  end

  def written_chunks
    chunks = []
    expect(AuditEvents::AiAuditEvents::WriteService).to have_received(:new).at_least(:once) do |chunk|
      chunks << chunk
    end
    chunks
  end

  def create_walk_state(**attributes)
    create(:ai_compliance_anthropic_session, namespace: group, anthropic_integration: integration,
      ai_governance_session: governance_session, session_xid: session_xid, **attributes)
  end

  before do
    allow(AuditEvents::AiAuditEvents::WriteService).to receive(:new).and_call_original
  end

  describe '#execute' do
    context 'when the governance session has no external id' do
      it 'stops without reading or creating a walk-state row', :aggregate_failures do
        allow(governance_session).to receive(:external_xid).and_return(nil)

        expect(execute.payload).to include(action: :stop)
        expect(a_request(:get, /anthropic/)).not_to have_been_made
        expect(walk_state).to be_nil
      end
    end

    context 'when the walk starts and more pages follow' do
      before do
        stub_messages(data: [message('clsm_3', '2026-07-01T15:30:00Z'), message('clsm_2')], next_page: 'page_2')
      end

      it 'creates the walk-state row and marks the walk as started', :freeze_time, :aggregate_failures do
        execute

        expect(walk_state).to have_attributes(
          namespace_id: group.id,
          anthropic_integration_id: integration.id,
          session_xid: session_xid,
          walk_started_at: Time.current,
          message_watermark: nil
        )
      end

      it 'continues with the next page, the newest message id and the walk start', :aggregate_failures do
        result = execute

        expect(result).to be_success
        expect(result.payload).to include(
          action: :continue,
          next_params: {
            'page_token' => 'page_2',
            'candidate_watermark' => 'clsm_3',
            'walk_started_at' => walk_state.walk_started_at.iso8601(6)
          }
        )
      end

      it 'writes the transformed messages through the write service', :aggregate_failures do
        execute

        expect(written_chunks).to contain_exactly(
          [
            have_attributes(
              event_name: 'ai_claude_user_input_received',
              created_at: Time.utc(2026, 7, 1, 15, 30),
              author_id: user.id,
              namespace_id: group.id,
              ai_governance_session_id: governance_session.id,
              details: hash_including('anthropic_user_id' => 'user_01ZYXWVU', 'text' => 'text of clsm_3')
            ),
            have_attributes(details: hash_including('text' => 'text of clsm_2'))
          ]
        )
        expect(written_chunks.flatten).to all(be_valid)
      end

      it 'stores the events against the governance session when storage is enabled' do
        allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
        group.namespace_settings.update!(ai_audit_events_storage_enabled: true)

        expect { execute }.to change {
          AuditEvents::AiAuditEvent.where(ai_governance_session_id: governance_session.id).count
        }.by(2)
      end

      it 'does not move the watermark before the walk reaches a stop' do
        execute

        expect(walk_state.message_watermark).to be_nil
      end

      it 'reports the page counts and the session length' do
        expect(execute.payload[:metadata]).to include(
          messages_read: 2, messages_ingested: 2, audit_events_written: 2,
          session_length_seconds: 6.5.hours.to_i
        )
      end

      it 'falls back to the governance session start when the envelope has no created_at' do
        envelope.delete(:created_at)

        expect(execute.payload[:metadata]).to include(session_length_seconds: 6.5.hours.to_i)
      end

      context 'when the response has no session envelope' do
        before do
          stub_messages(data: [message('clsm_3', '2026-07-01T15:30:00Z'), message('clsm_2')], next_page: 'page_2',
            session: nil)
        end

        it 'reports the session length from the governance session start' do
          expect(execute.payload[:metadata]).to include(session_length_seconds: 6.5.hours.to_i)
        end

        it 'writes the events without an Anthropic user id' do
          execute

          expect(written_chunks.flatten).to all(have_attributes(details: hash_including('anthropic_user_id' => nil)))
        end
      end

      context 'when the newest message of an idle session has a malformed created_at' do
        let!(:existing_walk) { create_walk_state(message_watermark: 'clsm_3') }

        before do
          stub_messages(data: [message('clsm_3', 'not-a-time'), message('clsm_2')], next_page: 'page_2')
        end

        it 'does not report the session length and still completes the walk', :aggregate_failures do
          expect(execute.payload[:metadata]).not_to have_key(:session_length_seconds)
          expect(existing_walk.reload).to have_attributes(message_watermark: 'clsm_3', walk_started_at: nil)
        end
      end

      context 'when the client returns parsed timestamps' do
        before do
          page = Ai::Compliance::Anthropic::Client::Page.new(
            data: [message('clsm_3', Time.utc(2026, 7, 1, 15, 30)).deep_stringify_keys],
            next_page: 'page_2',
            session: { 'created_at' => Time.utc(2026, 7, 1, 9) }
          )

          allow_next_instance_of(Ai::Compliance::Anthropic::Client) do |client|
            allow(client).to receive(:local_session_messages).and_return(page)
          end
        end

        it 'reports the session length without parsing them' do
          expect(execute.payload[:metadata]).to include(session_length_seconds: 6.5.hours.to_i)
        end
      end
    end

    context 'when a later page is the last one' do
      let!(:existing_walk) { create_walk_state(walk_started_at: 1.hour.ago) }
      let(:params) do
        {
          'page_token' => 'page_2',
          'candidate_watermark' => 'clsm_3',
          'walk_started_at' => existing_walk.reload.walk_started_at.iso8601(6)
        }
      end

      before do
        stub_messages(page: 'page_2', data: [message('clsm_1')])
      end

      it 'commits the candidate watermark, clears walk_started_at and stops', :aggregate_failures do
        result = execute(params)

        expect(result.payload).to include(action: :stop, metadata: hash_including(walk_completed: true))
        expect(existing_walk.reload).to have_attributes(message_watermark: 'clsm_3', walk_started_at: nil)
      end

      it 'commits nothing and raises for a retry when the write fails', :aggregate_failures do
        allow(AuditEvents::AiAuditEvents::WriteService).to receive(:new).and_raise(ActiveRecord::StatementInvalid)

        expect { execute(params) }.to raise_error(ActiveRecord::StatementInvalid)
        expect(existing_walk.reload).to have_attributes(message_watermark: nil, walk_started_at: be_present)
      end

      it 'does not report the session length' do
        expect(execute(params).payload[:metadata]).not_to have_key(:session_length_seconds)
      end

      context 'when a newer walk started after this one' do
        let!(:existing_walk) { create_walk_state(message_watermark: 'clsm_9', walk_started_at: 1.hour.ago) }
        let(:params) do
          { 'page_token' => 'page_2', 'candidate_watermark' => 'clsm_7', 'walk_started_at' => 2.hours.ago.iso8601(6) }
        end

        it 'does not move the watermark back or end the newer walk', :aggregate_failures do
          result = execute(params)

          expect(result.payload).to include(action: :stop, metadata: hash_including(stale_walk_skipped: true))
          expect(existing_walk.reload).to have_attributes(message_watermark: 'clsm_9', walk_started_at: be_present)
        end
      end
    end

    context 'when a message on the page cannot be stored' do
      where(:bad_created_at, :skip_reason) do
        [
          ['not-a-time', 'created_at is not an ISO 8601 time'],
          [nil, 'created_at is missing']
        ]
      end

      with_them do
        before do
          stub_messages(data: [message('clsm_2', bad_created_at), message('clsm_1')])
        end

        it 'skips and logs it, writes the rest, and commits the walk', :aggregate_failures do
          expect(Gitlab::AppJsonLogger).to receive(:warn).with({
            Labkit::Fields::CLASS_NAME => described_class.name,
            Labkit::Fields::LOG_MESSAGE => 'Skipped Claude Code transcript message',
            skip_reason: skip_reason,
            anthropic_message_id: 'clsm_2',
            ai_governance_session_id: governance_session.id
          }.stringify_keys)

          execute

          expect(written_chunks).to contain_exactly(
            [have_attributes(details: hash_including('text' => 'text of clsm_1'))]
          )
          expect(walk_state).to have_attributes(message_watermark: 'clsm_2', walk_started_at: nil)
        end
      end
    end

    context 'when the walk reaches the stored watermark' do
      let!(:existing_walk) { create_walk_state(message_watermark: 'clsm_2') }

      it 'sends only newer messages, commits the newest id and stops', :aggregate_failures do
        stub_messages(data: [message('clsm_4'), message('clsm_3'), message('clsm_2'), message('clsm_1')],
          next_page: 'page_2')

        expect(execute.payload).to include(action: :stop)
        expect(written_chunks).to contain_exactly(
          [have_attributes(details: hash_including('text' => 'text of clsm_4')),
            have_attributes(details: hash_including('text' => 'text of clsm_3'))]
        )
        expect(existing_walk.reload).to have_attributes(message_watermark: 'clsm_4', walk_started_at: nil)
      end

      it 'costs one page and writes nothing when the session is idle', :aggregate_failures do
        stub_messages(data: [message('clsm_2'), message('clsm_1')], next_page: 'page_2')

        execute

        expect(AuditEvents::AiAuditEvents::WriteService).not_to have_received(:new)
        expect(existing_walk.reload).to have_attributes(message_watermark: 'clsm_2', walk_started_at: nil)
      end
    end

    context 'when the transcript is empty' do
      before do
        stub_messages(data: [])
      end

      it 'finishes the walk without a watermark', :aggregate_failures do
        execute

        expect(walk_state).to have_attributes(message_watermark: nil, walk_started_at: nil)
        expect(AuditEvents::AiAuditEvents::WriteService).not_to have_received(:new)
      end

      it 'moves updated_at past created_at, recording a finished walk' do
        execute

        expect(walk_state.updated_at).to be > walk_state.created_at
      end
    end

    context 'when the first fetch fails before the walk starts' do
      it 'leaves a row that has never finished a walk', :aggregate_failures do
        stub_request(:get, messages_url).with(query: hash_including({})).to_return(status: 500)

        expect { execute }.to raise_error(Ai::Compliance::Anthropic::Client::Error)
        expect(walk_state).to have_attributes(message_watermark: nil, walk_started_at: nil)
        expect(walk_state.updated_at).to eq(walk_state.created_at)
      end
    end

    context 'when the first page is empty but points to a next page' do
      before do
        stub_messages(data: [], next_page: 'page_2')
        stub_messages(page: 'page_2', data: [message('clsm_2'), message('clsm_1')])
      end

      it 'commits the newest id from the first page with messages', :aggregate_failures do
        next_params = execute.payload[:next_params]

        expect(next_params).to eq('page_token' => 'page_2', 'walk_started_at' => walk_state.walk_started_at.iso8601(6))

        execute(next_params)

        expect(walk_state).to have_attributes(message_watermark: 'clsm_2', walk_started_at: nil)
      end
    end

    context 'when a page yields more events than one write holds' do
      before do
        stub_const("#{described_class}::EVENTS_PER_WRITE", 2)
        stub_messages(data: [message('clsm_3'), message('clsm_2'), message('clsm_1')])
      end

      it 'writes the events in chunks' do
        execute

        expect(written_chunks.map(&:size)).to eq([2, 1])
      end
    end

    context 'when the ClickHouse write buffer is above the limit' do
      let(:clickhouse_enabled) { true }
      let(:pending) { described_class::WRITE_BUFFER_PENDING_LIMIT + 1 }
      let(:walk_started_at) { 1.hour.ago.iso8601(6) }
      let(:params) do
        { 'page_token' => 'page_2', 'candidate_watermark' => 'clsm_5', 'walk_started_at' => walk_started_at }
      end

      let!(:existing_walk) { create_walk_state(message_watermark: 'clsm_1', walk_started_at: walk_started_at) }

      before do
        allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(clickhouse_enabled)
        allow(ClickHouse::WriteBuffer).to receive(:pending).with('ai_audit_events').and_return(pending)
        stub_messages(page: 'page_2', data: [message('clsm_3'), message('clsm_2')], next_page: 'page_3')
      end

      it 'reschedules the same page without writing or moving the watermark', :aggregate_failures do
        result = execute(params)

        expect(result.payload).to include(
          action: :reschedule, next_params: params, metadata: hash_including(write_buffer_rescheduled: true)
        )
        expect(AuditEvents::AiAuditEvents::WriteService).not_to have_received(:new)
        expect(existing_walk.reload).to have_attributes(message_watermark: 'clsm_1', walk_started_at: be_present)
      end

      it 'reschedules a first page as a fresh first page' do
        stub_messages(data: [message('clsm_4'), message('clsm_3')], next_page: 'page_2')

        expect(execute.payload).to include(action: :reschedule, next_params: hash_excluding('page_token'))
      end

      it 'still commits an idle session, which has nothing to write', :aggregate_failures do
        stub_messages(data: [message('clsm_1')], next_page: 'page_2')

        expect(execute.payload).to include(action: :stop)
        expect(existing_walk.reload).to have_attributes(message_watermark: 'clsm_1', walk_started_at: nil)
      end

      context 'when the buffer is at the limit' do
        let(:pending) { described_class::WRITE_BUFFER_PENDING_LIMIT }

        it 'writes the page', :aggregate_failures do
          expect(execute(params).payload).to include(action: :continue)
          expect(written_chunks.flatten.size).to eq(2)
        end
      end

      context 'when ClickHouse is not enabled' do
        let(:clickhouse_enabled) { false }

        it 'ignores a leftover buffer and writes the page', :aggregate_failures do
          expect(execute(params).payload).to include(action: :continue)
          expect(written_chunks.flatten.size).to eq(2)
        end
      end

      context 'when the rescheduled page token has expired' do
        before do
          stub_expired_cursor('page_2')
          stub_messages(data: [message('clsm_6'), message('clsm_5')], next_page: 'page_2b')
        end

        it 'restarts the walk from the newest page and reschedules that' do
          expect(execute(params).payload)
            .to include(action: :reschedule, next_params: hash_including('candidate_watermark' => 'clsm_6'))
            .and include(next_params: hash_excluding('page_token'))
        end
      end
    end

    context 'when the page cursor has expired' do
      let!(:existing_walk) { create_walk_state(message_watermark: 'clsm_1', walk_started_at: 25.hours.ago) }

      before do
        stub_expired_cursor('page_9')
        stub_messages(data: [message('clsm_5'), message('clsm_4')], next_page: 'page_2')
      end

      it 'restarts the walk without a page and carries the new newest id and start', :freeze_time,
        :aggregate_failures do
        result = execute(
          'page_token' => 'page_9', 'candidate_watermark' => 'clsm_3', 'walk_started_at' => 25.hours.ago.iso8601(6)
        )

        expect(result.payload).to include(
          action: :continue,
          next_params: {
            'page_token' => 'page_2', 'candidate_watermark' => 'clsm_5', 'walk_started_at' => Time.current.iso8601(6)
          },
          metadata: hash_including(walk_restarted: true)
        )
        expect(existing_walk.reload).to have_attributes(message_watermark: 'clsm_1', walk_started_at: Time.current)
      end
    end

    context 'when the first page reports an expired cursor' do
      it 'raises' do
        stub_expired_cursor(nil)

        expect { execute }.to raise_error(Ai::Compliance::Anthropic::Client::PageCursorExpiredError)
      end
    end

    context 'when the session no longer exists at Anthropic' do
      let!(:existing_walk) { create_walk_state(message_watermark: 'clsm_1', walk_started_at: 1.hour.ago) }

      it 'clears walk_started_at, keeps the watermark and stops', :aggregate_failures do
        stub_session_not_found(hash_including('page' => 'page_2'))

        result = execute(
          'page_token' => 'page_2', 'candidate_watermark' => 'clsm_3',
          'walk_started_at' => existing_walk.reload.walk_started_at.iso8601(6)
        )

        expect(result.payload).to include(action: :stop, metadata: hash_including(session_not_found: true))
        expect(existing_walk.reload).to have_attributes(message_watermark: 'clsm_1', walk_started_at: nil)
      end

      context 'when no walk-state row exists yet' do
        let!(:existing_walk) { nil }

        it 'records a finished walk' do
          stub_session_not_found

          execute

          expect(walk_state.updated_at).to be > walk_state.created_at
        end
      end
    end

    context 'when the page cursor does not advance' do
      it 'raises and commits nothing', :aggregate_failures do
        stub_messages(page: 'page_2', data: [message('clsm_1')], next_page: 'page_2')

        expect { execute('page_token' => 'page_2', 'candidate_watermark' => 'clsm_3') }
          .to raise_error(Ai::Compliance::Anthropic::Client::RequestError)
        expect(walk_state.message_watermark).to be_nil
      end
    end
  end
end
