# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Ai::DuoWorkflows::CreateCheckpointWriteBatchService, feature_category: :duo_agent_platform do
  describe '#execute' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }

    let(:workflow) { create(:duo_workflows_workflow, **container_params) }
    let(:container_params) { { project: project } }
    let(:task) { 'id2' }

    let(:params) do
      {
        thread_ts: 'checkpoint_id',
        checkpoint_writes: [
          { task: 'id1', idx: 0, channel: 'channel', write_type: 'type', data: 'data' },
          { task: task, idx: 0, channel: 'channel', write_type: 'type', data: 'data' }
        ]
      }
    end

    subject(:execute) do
      described_class.new(workflow: workflow, params: params).execute
    end

    it 'stores checkpoint writes' do
      expect { execute }.to change { Ai::DuoWorkflows::CheckpointWrite.count }.by(2)
      expect(execute).to be_success
      expect(Ai::DuoWorkflows::CheckpointWrite.distinct.pluck('project_id')).to eq([project.id])
    end

    context 'when namespace-level workflow' do
      let(:container_params) { { namespace: group } }

      it 'stores checkpoint writes' do
        expect { execute }.to change { Ai::DuoWorkflows::CheckpointWrite.count }.by(2)
        expect(execute).to be_success
        expect(Ai::DuoWorkflows::CheckpointWrite.distinct.pluck('namespace_id')).to eq([group.id])
      end
    end

    context 'with invalid params' do
      let(:task) { '' }

      it "doesn't store any writes" do
        expect { execute }.not_to change { Ai::DuoWorkflows::CheckpointWrite.count }
        expect(execute).to be_error.and have_attributes(message: "Validation failed: Task can't be blank")
      end
    end

    it 'does not log a limit warning' do
      allow(Gitlab::AppLogger).to receive(:warn).and_call_original
      expect(Gitlab::AppLogger).not_to receive(:warn)
        .with(hash_including('message' => 'Duo Workflow checkpoint write batch exceeds limits'))

      execute
    end

    shared_examples 'a batch over the limits' do |limit_type, error_message|
      before do
        allow(Gitlab::AppLogger).to receive(:warn).and_call_original
      end

      it 'rejects the batch and logs it' do
        expect(Gitlab::AppLogger).to receive(:warn).with(
          hash_including(
            'message' => 'Duo Workflow checkpoint write batch exceeds limits',
            'limit_type' => limit_type,
            'enforced' => true
          )
        )

        expect { execute }.not_to change { Ai::DuoWorkflows::CheckpointWrite.count }
        expect(execute).to be_error.and have_attributes(message: error_message, http_status: :bad_request)
      end

      context 'when duo_workflow_enforce_checkpoint_write_limits is disabled' do
        before do
          stub_feature_flags(duo_workflow_enforce_checkpoint_write_limits: false)
        end

        it 'stores the writes and logs the batch' do
          expect(Gitlab::AppLogger).to receive(:warn).with(
            hash_including('limit_type' => limit_type, 'enforced' => false)
          )

          expect { execute }.to change { Ai::DuoWorkflows::CheckpointWrite.count }
            .by(params[:checkpoint_writes].size)
          expect(execute).to be_success
        end
      end
    end

    context 'with more writes than the limit' do
      let(:params) do
        writes = Array.new(described_class::MAX_WRITES_PER_BATCH + 1) do |idx|
          { task: 'id1', idx: idx, channel: 'channel', write_type: 'type', data: 'data' }
        end

        { thread_ts: 'checkpoint_id', checkpoint_writes: writes }
      end

      it_behaves_like 'a batch over the limits', 'too_many_writes',
        'Too many checkpoint writes: 11 exceeds the limit of 10'
    end

    context 'with writes exactly at the count and size limits' do
      let(:params) do
        data = 'a' * described_class::MAX_DATA_BYTESIZE
        writes = Array.new(described_class::MAX_WRITES_PER_BATCH) do |idx|
          { task: 'id1', idx: idx, channel: 'channel', write_type: 'type', data: data }
        end

        { thread_ts: 'checkpoint_id', checkpoint_writes: writes }
      end

      it 'stores the writes' do
        expect { execute }.to change { Ai::DuoWorkflows::CheckpointWrite.count }.by(10)
        expect(execute).to be_success
      end
    end

    context 'with write data over the size limit' do
      before do
        params[:checkpoint_writes].last[:data] = 'a' * (described_class::MAX_DATA_BYTESIZE + 1)
      end

      it_behaves_like 'a batch over the limits', 'data_too_large',
        'Checkpoint write data exceeds the limit of 1024 bytes'
    end

    %i[finished stopped failed].each do |status|
      context "when the workflow is #{status}" do
        let(:workflow) { create(:duo_workflows_workflow, status, **container_params) }

        it_behaves_like 'a batch over the limits', 'terminal_session', "Cannot write checkpoints to a #{status} session"
      end
    end
  end
end
