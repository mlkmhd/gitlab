# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Messaging::ServerSideTurnWorker, feature_category: :duo_agent_platform do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }

  let(:callback_context) { { 'adapter' => 'slack', 'channel_id' => 'C1' } }

  let_it_be_with_reload(:workflow) do
    create(:duo_workflows_workflow, :running, user: user, project: project,
      workflow_definition: 'slack_assistant/v1', goal: 'What does this project do?')
  end

  let(:adapter) { instance_double(Ai::Messaging::Adapters::Slack) }
  let(:execution_result) { ServiceResponse.success(payload: { workflow: workflow }) }

  subject(:worker) { described_class.new }

  before do
    workflow.update!(messaging_callback_context: callback_context)

    allow(Ai::Messaging::Adapters::Slack).to receive(:from_callback_context).and_return(adapter)
    allow(adapter).to receive_messages(deliver_result: true, on_flow_completed: nil, on_flow_failed: nil)

    allow_next_instance_of(Ai::DuoWorkflows::ServerSideExecutionService) do |service|
      allow(service).to receive(:execute).and_return(execution_result)
    end
  end

  describe '#perform' do
    it 'runs the turn with the goal recorded on the workflow' do
      expect(Ai::DuoWorkflows::ServerSideExecutionService).to receive(:new)
        .with(workflow: workflow, goal: workflow.goal, approval: nil, context: {}, detached: true)
        .and_call_original

      worker.perform(workflow.id)
    end

    it 'forwards the run context to the execution service, dropping unknown keys' do
      expect(Ai::DuoWorkflows::ServerSideExecutionService).to receive(:new)
        .with(workflow: workflow, goal: workflow.goal, approval: nil,
          context: { client_context: 'Slack context', event_type: 'mention' }, detached: true)
        .and_call_original

      worker.perform(workflow.id, nil, nil, { 'client_context' => 'Slack context', 'event_type' => 'mention',
        'unknown' => 'x' })
    end

    it 'forwards an approval so a resume runs through the same worker' do
      approval = { 'approval' => { 'approved' => true } }

      expect(Ai::DuoWorkflows::ServerSideExecutionService).to receive(:new)
        .with(workflow: workflow, goal: workflow.goal, approval: approval, context: {}, detached: true)
        .and_call_original

      worker.perform(workflow.id, approval)
    end

    # The turn can pause before Workhorse answers, and CallbackWorker reads this then.
    it 'marks the turn detached before asking Workhorse for it' do
      allow_next_instance_of(Ai::DuoWorkflows::ServerSideExecutionService) do |service|
        allow(service).to receive(:execute) do
          expect(workflow.reload.messaging_callback_context['detached_turn']).to be(true)

          execution_result
        end
      end

      worker.perform(workflow.id)
    end

    context 'when duo_workflow_detached_server_side_execution is disabled' do
      before do
        stub_feature_flags(duo_workflow_detached_server_side_execution: false)
      end

      it 'waits for the turn to end', :aggregate_failures do
        expect(Ai::DuoWorkflows::ServerSideExecutionService).to receive(:new)
          .with(workflow: workflow, goal: workflow.goal, approval: nil, context: {}, detached: false)
          .and_call_original

        worker.perform(workflow.id)

        expect(workflow.reload.messaging_callback_context).not_to have_key('detached_turn')
      end
    end

    context 'when Workhorse took the turn on detached' do
      let(:execution_result) { ServiceResponse.success(payload: { workflow: workflow, detached: true }) }

      before do
        create(:duo_workflows_checkpoint, workflow: workflow, project: project,
          checkpoint: { 'channel_values' => { 'ui_chat_log' => [
            { 'message_type' => 'agent', 'content' => 'Looking into it.' }
          ] } })
      end

      # The turn is still going: delivering would post an interim message and
      # claim the delivery, suppressing the answer CallbackWorker delivers later.
      it 'delivers nothing and leaves the delivery unclaimed', :aggregate_failures do
        worker.perform(workflow.id)

        expect(adapter).not_to have_received(:deliver_result)
        expect(adapter).not_to have_received(:on_flow_failed)
        expect(workflow.reload.messaging_callback_context['delivered_at']).to be_nil
      end
    end

    context 'when the turn paused for an approval' do
      before do
        create(:duo_workflows_checkpoint, workflow: workflow, project: project,
          checkpoint: { 'channel_values' => { 'ui_chat_log' => [
            { 'message_type' => 'agent', 'content' => 'I need to run a command first.' }
          ] } })

        workflow.require_tool_call_approval!
      end

      # Delivering here would post an interim message and claim the delivery,
      # suppressing the real answer once the run resumes and finishes.
      it 'delivers nothing and leaves the delivery unclaimed', :aggregate_failures do
        worker.perform(workflow.id)

        expect(adapter).not_to have_received(:deliver_result)
        expect(adapter).not_to have_received(:on_flow_completed)
        expect(adapter).not_to have_received(:on_flow_failed)
        expect(workflow.reload.messaging_callback_context['delivered_at']).to be_nil
      end
    end

    context 'when the turn is answering a later message' do
      it 'runs the turn with that message rather than the session goal' do
        expect(Ai::DuoWorkflows::ServerSideExecutionService).to receive(:new)
          .with(workflow: workflow, goal: 'And who maintains it?', approval: nil, context: {}, detached: true)
          .and_call_original

        worker.perform(workflow.id, nil, 'And who maintains it?')
      end
    end

    context 'when the turn produced an answer' do
      before do
        create(:duo_workflows_checkpoint, workflow: workflow, project: project,
          checkpoint: { 'channel_values' => { 'ui_chat_log' => [
            { 'message_type' => 'user', 'content' => 'What does this project do?' },
            { 'message_type' => 'agent', 'content' => 'It runs GitLab.' }
          ] } })

        workflow.require_input!
      end

      it 'delivers it and marks the flow completed', :aggregate_failures do
        worker.perform(workflow.id)

        expect(adapter).to have_received(:deliver_result)
          .with(callback_context: hash_including(callback_context), message: 'It runs GitLab.', workflow: workflow)
        expect(adapter).to have_received(:on_flow_completed)
      end

      it 'claims the delivery so live progress stops re-rendering over the answer' do
        worker.perform(workflow.id)

        expect(workflow.reload.messaging_callback_context['delivered_at']).to be_present
      end

      it 'does not deliver twice when the job is retried' do
        worker.perform(workflow.id)
        worker.perform(workflow.id)

        expect(adapter).to have_received(:deliver_result).once
      end
    end

    context 'when the turn failed' do
      let(:execution_result) { ServiceResponse.error(message: 'forbidden', reason: :forbidden) }

      it 'reports the reason to the surface', :aggregate_failures do
        worker.perform(workflow.id)

        expect(adapter).to have_received(:on_flow_failed)
          .with(callback_context: hash_including(callback_context), error: :forbidden, workflow: workflow)
        expect(adapter).not_to have_received(:deliver_result)
      end

      it 'claims the delivery so the failure is reported once' do
        worker.perform(workflow.id)

        expect(workflow.reload.messaging_callback_context['delivered_at']).to be_present
      end

      it 'does not report again when the drop event reaches CallbackWorker' do
        worker.perform(workflow.id)
        workflow.reload.drop!

        expect(adapter).to have_received(:on_flow_failed).once
      end

      context 'when the outcome was already delivered' do
        before do
          workflow.claim_messaging_callback_delivery
        end

        it 'reports nothing' do
          worker.perform(workflow.id)

          expect(adapter).not_to have_received(:on_flow_failed)
        end
      end
    end

    it 'clears a stop signal left by an earlier stop before reading the workflow' do
      expect(Gitlab::DuoWorkflow::WorkhorseStopSignal).to receive(:clear).with(workflow.id).ordered
      expect(Ai::DuoWorkflows::Workflow).to receive(:find_by_id).with(workflow.id).ordered.and_call_original

      worker.perform(workflow.id)
    end

    it 'reads the workflow from the primary so a stop committed since the enqueue is seen' do
      lb_session = ::Gitlab::Database::LoadBalancing::SessionMap.current(Ai::DuoWorkflows::Workflow.load_balancer)
      allow(::Gitlab::Database::LoadBalancing::SessionMap).to receive(:current).and_call_original
      allow(::Gitlab::Database::LoadBalancing::SessionMap)
        .to receive(:current).with(Ai::DuoWorkflows::Workflow.load_balancer).and_return(lb_session)
      expect(lb_session).to receive(:use_primary).and_call_original

      worker.perform(workflow.id)
    end

    context 'when clearing the stop signal fails' do
      let(:error) { ::RedisClient::CannotConnectError.new('redis down') }

      before do
        allow(Gitlab::Workhorse).to receive(:cleanup_key).and_raise(error)
      end

      it 'reports the error and still runs the turn' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error, workflow_id: workflow.id)
        expect_next_instance_of(Ai::DuoWorkflows::ServerSideExecutionService) do |service|
          expect(service).to receive(:execute).and_return(execution_result)
        end

        worker.perform(workflow.id)
      end
    end

    context 'when Workhorse is unavailable before the turn starts' do
      let(:execution_result) { ServiceResponse.error(message: 'draining', reason: :workhorse_unavailable) }

      it 'raises for a Sidekiq retry without reporting or claiming', :aggregate_failures do
        expect { worker.perform(workflow.id) }.to raise_error(described_class::WorkhorseUnavailableError)

        expect(adapter).not_to have_received(:on_flow_failed)
        expect(workflow.reload.messaging_callback_context['delivered_at']).to be_nil
      end

      it 'clears the started marker so the retry hands the message over' do
        expect { worker.perform(workflow.id) }.to raise_error(described_class::WorkhorseUnavailableError)

        expect(workflow.reload.messaging_callback_context['turn_started']).to be_nil
      end

      it 'clears the detached marker, since no detached run started' do
        expect { worker.perform(workflow.id) }.to raise_error(described_class::WorkhorseUnavailableError)

        expect(workflow.reload.messaging_callback_context['detached_turn']).to be_nil
      end
    end

    context 'when the workflow is locked before the turn starts' do
      let(:execution_result) { ServiceResponse.error(message: 'locked', reason: :workflow_locked) }

      # A re-pushed job whose first run is still going, or a concurrent message's turn.
      context 'when a detached turn is running' do
        # The turn starts while the request is in flight, so the job's copy is stale.
        before do
          workflow.require_input!

          allow_next_instance_of(Ai::DuoWorkflows::ServerSideExecutionService) do |service|
            allow(service).to receive(:execute) do
              Ai::DuoWorkflows::Workflow.id_in(workflow.id)
                .update_all(status: Ai::DuoWorkflows::Workflow.state_machines[:status].states[:running].value)

              execution_result
            end
          end
        end

        it 'leaves the outcome to that turn without raising', :aggregate_failures do
          expect { worker.perform(workflow.id) }.not_to raise_error

          expect(adapter).not_to have_received(:on_flow_failed)
          expect(workflow.reload.messaging_callback_context['delivered_at']).to be_nil
        end
      end

      context 'when the workflow is not running yet' do
        before do
          workflow.require_input!
        end

        it 'raises for a Sidekiq retry without reporting', :aggregate_failures do
          expect { worker.perform(workflow.id) }.to raise_error(described_class::WorkflowLockedError)

          expect(adapter).not_to have_received(:on_flow_failed)
        end
      end

      # The streaming run that held the lock ended with its connection, so the lock frees soon.
      context 'when duo_workflow_detached_server_side_execution is disabled' do
        before do
          stub_feature_flags(duo_workflow_detached_server_side_execution: false)
        end

        it 'raises for a Sidekiq retry' do
          expect { worker.perform(workflow.id) }.to raise_error(described_class::WorkflowLockedError)
        end
      end
    end

    it 'marks the turn started before handing its message to the run' do
      allow_next_instance_of(Ai::DuoWorkflows::ServerSideExecutionService) do |service|
        allow(service).to receive(:execute) do
          expect(workflow.reload.messaging_callback_context['turn_started']).to be(true)

          execution_result
        end
      end

      worker.perform(workflow.id)
    end

    # Sidekiq runs the job again (a retry or a deploy re-push) after the run took the message.
    context 'when the run already took the turn\'s message' do
      let(:callback_context) { { 'adapter' => 'slack', 'channel_id' => 'C1', 'turn_started' => true } }

      context 'when the run is still going' do
        it 'resumes it without resending the message or the approval' do
          expect(Ai::DuoWorkflows::ServerSideExecutionService).to receive(:new)
            .with(workflow: workflow, goal: nil, approval: nil, context: {}, detached: true)
            .and_return(instance_double(Ai::DuoWorkflows::ServerSideExecutionService, execute: execution_result))

          worker.perform(workflow.id, { 'approval' => { 'approved' => true } }, 'And who maintains it?')
        end
      end

      context 'when the turn ended at a wait for the user' do
        before do
          create(:duo_workflows_checkpoint, workflow: workflow, project: project,
            checkpoint: { 'channel_values' => { 'ui_chat_log' => [
              { 'message_type' => 'agent', 'content' => 'It runs GitLab.' }
            ] } })

          workflow.require_input!
        end

        it 'delivers the answer without running the turn again', :aggregate_failures do
          expect(Ai::DuoWorkflows::ServerSideExecutionService).not_to receive(:new)

          worker.perform(workflow.id, nil, 'What does this project do?')

          expect(adapter).to have_received(:deliver_result)
            .with(callback_context: hash_including(callback_context), message: 'It runs GitLab.', workflow: workflow)
        end
      end

      context 'when the run parked at a tool approval' do
        before do
          workflow.require_tool_call_approval!
        end

        it 'neither runs the turn again nor delivers anything', :aggregate_failures do
          expect(Ai::DuoWorkflows::ServerSideExecutionService).not_to receive(:new)

          worker.perform(workflow.id, nil, 'What does this project do?')

          expect(adapter).not_to have_received(:deliver_result)
          expect(adapter).not_to have_received(:on_flow_failed)
        end
      end

      context 'when Workhorse refuses this attempt before starting it' do
        let(:execution_result) { ServiceResponse.error(message: 'draining', reason: :workhorse_unavailable) }

        it 'keeps the marker, since an earlier attempt\'s run took the message' do
          expect { worker.perform(workflow.id) }.to raise_error(described_class::WorkhorseUnavailableError)

          expect(workflow.reload.messaging_callback_context['turn_started']).to be(true)
        end
      end
    end

    # A retry after the turn ran, for example a re-pushed job whose run finished during the backoff.
    context 'when the turn was already delivered' do
      before do
        workflow.claim_messaging_callback_delivery
      end

      it 'does not run the turn again' do
        expect(Ai::DuoWorkflows::ServerSideExecutionService).not_to receive(:new)

        worker.perform(workflow.id)
      end
    end

    context 'when the workflow no longer exists' do
      it 'does nothing' do
        expect(Ai::DuoWorkflows::ServerSideExecutionService).not_to receive(:new)

        worker.perform(non_existing_record_id)
      end
    end

    context 'when the session was failed while the turn was queued' do
      before do
        workflow.drop!
      end

      it 'neither runs the turn nor delivers anything', :aggregate_failures do
        expect(Ai::DuoWorkflows::ServerSideExecutionService).not_to receive(:new)
        expect(Gitlab::AppLogger).to receive(:info)
          .with(message: 'Duo Messaging: Session already terminal; not running the turn', workflow_id: workflow.id)

        worker.perform(workflow.id)

        expect(adapter).not_to have_received(:deliver_result)
        expect(adapter).not_to have_received(:on_flow_failed)
      end
    end

    context 'when the workflow has no messaging callback context' do
      before do
        workflow.update!(messaging_callback_context: nil)
      end

      it 'still runs the turn, but delivers nothing', :aggregate_failures do
        expect(Ai::DuoWorkflows::ServerSideExecutionService).to receive(:new).and_call_original

        worker.perform(workflow.id)

        expect(adapter).not_to have_received(:deliver_result)
        expect(workflow.reload.messaging_callback_context).to be_nil
      end

      context 'when the turn failed' do
        where(:reason, :drop_reason) do
          :forbidden               | 'start_failed'
          :execute_workflow_failed | 'start_failed'
          :flow_failed             | 'no_status_reported'
        end

        with_them do
          let(:execution_result) { ServiceResponse.error(message: 'failed', reason: reason) }

          it 'drops the session rather than leave it to the stuck session cleanup', :aggregate_failures do
            expect(::Gitlab::Audit::Auditor).to receive(:audit)
              .with(hash_including(name: 'duo_session_failed', author: described_class::SYSTEM_AUTHOR))

            expect { worker.perform(workflow.id) }.to trigger_internal_events('agent_platform_session_dropped')
              .with(category: described_class.name, user: user, project: project,
                additional_properties: { drop_reason: drop_reason })

            expect(workflow.reload).to be_failed
            expect(workflow.drop_reason).to eq(drop_reason)
          end
        end

        context 'when the session is paused' do
          let(:execution_result) { ServiceResponse.error(message: 'rate limited', reason: :execute_workflow_failed) }

          before do
            workflow.require_input!
          end

          it 'keeps it resumable' do
            worker.perform(workflow.id)

            expect(workflow.reload).to be_input_required
          end
        end
      end

      context 'when another turn holds the workflow lock' do
        let(:execution_result) { ServiceResponse.error(message: 'locked', reason: :workflow_locked) }

        it 'leaves the session to that turn' do
          worker.perform(workflow.id)

          expect(workflow.reload).to be_running
        end
      end

      context 'when Workhorse is unavailable before the turn starts' do
        let(:execution_result) { ServiceResponse.error(message: 'draining', reason: :workhorse_unavailable) }

        it 'raises for a Sidekiq retry rather than dropping the session', :aggregate_failures do
          expect { worker.perform(workflow.id) }.to raise_error(described_class::WorkhorseUnavailableError)

          expect(workflow.reload).to be_running
        end
      end

      context 'when the session failed during the turn' do
        let(:execution_result) { ServiceResponse.error(message: 'failed', reason: :flow_failed) }

        before do
          allow_next_instance_of(Ai::DuoWorkflows::ServerSideExecutionService) do |service|
            allow(service).to receive(:execute) do
              Ai::DuoWorkflows::Workflow.find(workflow.id).drop!
              execution_result
            end
          end
        end

        it 'keeps the status it ended with' do
          worker.perform(workflow.id)

          expect(workflow.reload.drop_reason).to be_nil
        end
      end
    end

    describe 'the turn claim', :clean_gitlab_redis_shared_state do
      let(:claim) { Ai::DuoWorkflows::TurnClaim.new(workflow.id) }

      before do
        claim.obtain
      end

      it 'keeps it once the turn has started, for the session to release when it resumes' do
        worker.perform(workflow.id)

        expect(claim.obtain).to be(false)
      end

      it 'releases it when the turn failed' do
        allow_next_instance_of(Ai::DuoWorkflows::ServerSideExecutionService) do |service|
          allow(service).to receive(:execute)
            .and_return(ServiceResponse.error(message: 'locked', reason: :workflow_locked))
        end

        worker.perform(workflow.id)

        expect(claim.obtain).to be(true)
      end

      it 'keeps it when the turn raises, for the retry that runs the same turn' do
        allow_next_instance_of(Ai::DuoWorkflows::ServerSideExecutionService) do |service|
          allow(service).to receive(:execute).and_raise(StandardError, 'boom')
        end

        expect { worker.perform(workflow.id) }.to raise_error(StandardError, 'boom')
        expect(claim.obtain).to be(false)
      end
    end
  end

  describe '.sidekiq_retry_in' do
    using RSpec::Parameterized::TableSyntax

    subject(:retry_in) { described_class.sidekiq_retry_in_block.call(count, exception, {}) }

    where(:count, :exception, :expected) do
      0 | described_class::WorkhorseUnavailableError.new | 10
      1 | described_class::WorkflowLockedError.new       | 20
      2 | described_class::WorkflowLockedError.new       | 30
      3 | described_class::WorkhorseUnavailableError.new | :kill
      0 | StandardError.new                              | nil
    end

    with_them do
      it { is_expected.to eq(expected) }
    end
  end

  describe '.sidekiq_retries_exhausted' do
    let(:job) { { 'args' => [workflow.id, nil, nil, {}] } }

    subject(:exhaust) { described_class.sidekiq_retries_exhausted_block.call(job, exception) }

    context 'when Workhorse stayed unavailable' do
      let(:exception) { described_class::WorkhorseUnavailableError.new }

      it 'reports that the turn did not start and claims the delivery', :aggregate_failures do
        exhaust

        expect(adapter).to have_received(:on_flow_failed)
          .with(callback_context: hash_including(callback_context), error: :execute_workflow_failed,
            workflow: workflow)
        expect(workflow.reload.messaging_callback_context['delivered_at']).to be_present
      end

      # Sidekiq only logs a raise from this hook.
      it 'tracks an error instead of raising it' do
        error = StandardError.new('no installation')
        allow(Ai::Messaging::Adapters::Slack).to receive(:from_callback_context).and_raise(error)

        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error, workflow_id: workflow.id)
        expect { exhaust }.not_to raise_error
      end

      it 'releases the turn claim the retries kept', :clean_gitlab_redis_shared_state do
        claim = Ai::DuoWorkflows::TurnClaim.new(workflow.id)
        claim.obtain

        exhaust

        expect(claim.obtain).to be(true)
      end

      context 'when the workflow has no messaging callback context' do
        before do
          workflow.update!(messaging_callback_context: nil)
        end

        it 'drops the session rather than leave it to the stuck session cleanup', :aggregate_failures do
          exhaust

          expect(workflow.reload).to be_failed
          expect(workflow.drop_reason).to eq('start_failed')
        end
      end
    end

    context 'when the workflow stayed locked' do
      let(:exception) { described_class::WorkflowLockedError.new }

      context 'when it is not running' do
        before do
          workflow.require_input!
        end

        it 'reports the lock' do
          exhaust

          expect(adapter).to have_received(:on_flow_failed)
            .with(callback_context: hash_including(callback_context), error: :workflow_locked, workflow: workflow)
        end

        context 'when the workflow has no messaging callback context' do
          before do
            workflow.update!(messaging_callback_context: nil)
          end

          it 'leaves the session to the turn holding the lock' do
            exhaust

            expect(workflow.reload).to be_input_required
          end
        end
      end

      context 'when it is running' do
        it 'leaves the outcome to the running turn', :aggregate_failures do
          exhaust

          expect(adapter).not_to have_received(:on_flow_failed)
          expect(workflow.reload.messaging_callback_context['delivered_at']).to be_nil
        end
      end
    end

    context 'when another error exhausted the retries' do
      let(:exception) { StandardError.new }

      it 'reports nothing' do
        exhaust

        expect(adapter).not_to have_received(:on_flow_failed)
      end
    end

    context 'when the workflow no longer exists' do
      let(:job) { { 'args' => [non_existing_record_id] } }
      let(:exception) { described_class::WorkhorseUnavailableError.new }

      it 'reports nothing' do
        exhaust

        expect(adapter).not_to have_received(:on_flow_failed)
      end
    end
  end
end
