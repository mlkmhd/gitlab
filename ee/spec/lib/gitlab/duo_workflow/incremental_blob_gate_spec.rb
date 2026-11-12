# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::DuoWorkflow::IncrementalBlobGate, feature_category: :duo_agent_platform do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  let(:incremental_checkpoints_enabled) { true }
  let(:workflow) do
    create(:duo_workflows_workflow, project: project,
      incremental_checkpoints_enabled: incremental_checkpoints_enabled)
  end

  subject(:gate) { described_class.new(workflow) }

  describe '#reconstruct?' do
    subject { gate.reconstruct? }

    it { is_expected.to be(true) }

    context 'when the workflow does not have incremental checkpoints enabled' do
      let(:incremental_checkpoints_enabled) { false }

      it { is_expected.to be(false) }
    end

    context 'when the newest header records no channel membership' do
      before do
        create(:duo_workflows_checkpoint_header, workflow: workflow, project: project, channel_keys: nil)
      end

      it { is_expected.to be(true) }

      # The batch header loaders call this for a page of workflows before they fetch headers.
      it 'runs no checkpoint header query' do
        gate # build outside the recorder so the workflow insert does not count

        recorder = ActiveRecord::QueryRecorder.new { gate.reconstruct? }

        expect(recorder.log).not_to include(a_string_matching(/checkpoint_headers/))
      end

      it 'is excluded by #read?' do
        expect(gate.read?).to be(false)
      end
    end
  end

  describe '#read?' do
    subject { gate.read? }

    context 'when the newest header records its channel membership' do
      before do
        create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-1', channel_keys: [])
        create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-2',
          channel_keys: %w[status ui_chat_log])
      end

      it { is_expected.to be(true) }
    end

    context 'when the newest header records no channel membership' do
      before do
        create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-1', channel_keys: nil)
      end

      it { is_expected.to be(false) }
    end

    # Only the newest header is checked, so a time-travel read of the older one folds
    # without a membership. Accepted: those headers age out with their partition.
    context 'when an older header records no channel membership' do
      before do
        create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-1', channel_keys: nil)
        create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: 'ts-2', channel_keys: %w[status])
      end

      it { is_expected.to be(true) }
    end

    context 'when the workflow has no headers' do
      it { is_expected.to be(true) }
    end

    context 'when the workflow does not have incremental checkpoints enabled' do
      let(:incremental_checkpoints_enabled) { false }

      it { is_expected.to be(false) }
    end
  end
end
