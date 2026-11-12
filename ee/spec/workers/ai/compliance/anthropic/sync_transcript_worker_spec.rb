# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Compliance::Anthropic::SyncTranscriptWorker, feature_category: :ai_governance do
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be(:integration) { create(:ai_compliance_anthropic_integration, namespace: group, enabled: true) }
  let_it_be(:session_xid) { 'clls_01HxKpLmNoPqRsTuVwXyZaBc' }
  let_it_be(:governance_session) do
    create(:ai_governance_session, :external, namespace: group, external_xid: session_xid)
  end

  let(:messages_url) { "https://api.anthropic.com/v1/compliance/apps/sessions/local/#{session_xid}/messages" }
  let(:params) { { 'page_token' => 'page_2', 'candidate_watermark' => 'clsm_3' } }
  let(:next_params) { { 'page_token' => 'page_3', 'candidate_watermark' => 'clsm_3' } }
  let(:payload) { { action: :stop, next_params: nil, metadata: { walk_completed: true } } }
  let(:worker) { described_class.new }

  def perform(integration_id: integration.id, ai_governance_session_id: governance_session.id)
    worker.perform(integration_id, ai_governance_session_id, params)
  end

  def stub_service
    allow_next_instance_of(Ai::Compliance::Anthropic::Transcripts::SyncPageService,
      integration, governance_session, params) do |service|
      allow(service).to receive(:execute).and_return(ServiceResponse.success(payload: payload))
    end
  end

  before do
    stub_feature_flags(claude_code_compliance_api_ingestion: group)
    allow(described_class).to receive(:perform_async)
    allow(described_class).to receive(:perform_in)
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [integration.id, governance_session.id] }

    before do
      stub_request(:get, messages_url).with(query: hash_including({})).to_return(
        status: 200, headers: { 'Content-Type' => 'application/json' },
        body: { session: { id: session_xid }, data: [], next_page: nil }.to_json
      )
    end
  end

  it 'has the expected worker attributes', :aggregate_failures do
    expect(described_class.get_feature_category).to eq(:ai_governance)
    expect(described_class.get_sidekiq_options['retry']).to eq(3)
    expect(described_class.worker_has_external_dependencies?).to be(true)
    expect(described_class.get_concurrency_limit).to eq(10)
    expect(described_class.loggable_arguments).to be_empty
  end

  describe '#perform' do
    shared_examples 'does nothing' do
      it 'does not call the service' do
        expect(Ai::Compliance::Anthropic::Transcripts::SyncPageService).not_to receive(:new)

        perform_job
      end
    end

    context 'when the integration does not exist' do
      it_behaves_like 'does nothing' do
        subject(:perform_job) { perform(integration_id: non_existing_record_id) }
      end
    end

    context 'when the integration is disabled' do
      let_it_be(:integration) { create(:ai_compliance_anthropic_integration, enabled: false) }

      it_behaves_like 'does nothing' do
        subject(:perform_job) { perform }
      end
    end

    context 'when the feature flag is disabled for the group' do
      before do
        stub_feature_flags(claude_code_compliance_api_ingestion: false)
      end

      it_behaves_like 'does nothing' do
        subject(:perform_job) { perform }
      end
    end

    context 'when the governance session does not exist' do
      it_behaves_like 'does nothing' do
        subject(:perform_job) { perform(ai_governance_session_id: non_existing_record_id) }
      end
    end

    context 'when the governance session belongs to another namespace' do
      let_it_be(:integration) { create(:ai_compliance_anthropic_integration, enabled: true) }

      before do
        stub_feature_flags(claude_code_compliance_api_ingestion: integration.namespace)
      end

      it_behaves_like 'does nothing' do
        subject(:perform_job) { perform }
      end
    end

    context 'when the service stops the walk' do
      it 'logs the page metadata and enqueues nothing', :aggregate_failures do
        stub_service

        expect(worker).to receive(:log_hash_metadata_on_done).with({ walk_completed: true })

        perform

        expect(described_class).not_to have_received(:perform_async)
        expect(described_class).not_to have_received(:perform_in)
      end
    end

    context 'when the service continues with the next page' do
      let(:payload) { { action: :continue, next_params: next_params, metadata: {} } }

      it 'enqueues the next page' do
        stub_service

        perform

        expect(described_class).to have_received(:perform_async)
          .with(integration.id, governance_session.id, next_params)
      end
    end

    context 'when the service reschedules the page' do
      let(:payload) { { action: :reschedule, next_params: params, metadata: { write_buffer_rescheduled: true } } }

      it 'counts the reschedule and enqueues the same page after the delay', :aggregate_failures do
        stub_service

        expect(described_class::WRITE_BUFFER_RESCHEDULES_COUNTER).to receive(:increment)

        perform

        expect(described_class).to have_received(:perform_in)
          .with(described_class::WRITE_BUFFER_RESCHEDULE_DELAY, integration.id, governance_session.id, params)
        expect(described_class).not_to have_received(:perform_async)
      end
    end
  end

  describe '.sidekiq_retries_exhausted' do
    let(:job) { { 'args' => [integration.id, governance_session.id, params] } }

    it 'logs the failed walk without its page token' do
      expect(Gitlab::AppJsonLogger).to receive(:error).with(
        Labkit::Fields::CLASS_NAME => described_class.name,
        Labkit::Fields::LOG_MESSAGE => 'Claude Code transcript walk failed: retries exhausted',
        Labkit::Fields::ERROR_TYPE => 'Ai::Compliance::Anthropic::Client::RequestError',
        Labkit::Fields::ERROR_MESSAGE => 'boom',
        :ai_governance_session_id => governance_session.id
      )

      described_class.sidekiq_retries_exhausted_block.call(job, Ai::Compliance::Anthropic::Client::RequestError.new('boom'))
    end
  end
end
