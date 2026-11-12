import waitForPromises from 'helpers/wait_for_promises';
import {
  loadActiveWorkflowWithRetry,
  isThreadLoadAborted,
  readCheckpointMessages,
} from 'ee/ai/duo_agentic_chat/services/load_active_workflow';
import { THREAD_LOAD_RETRY_DELAY_MS } from 'ee/ai/duo_agentic_chat/constants';
import {
  MOCK_FETCH_WORKFLOW_LATEST_CHECKPOINT_RESPONSE,
  MOCK_GOAL,
  MOCK_WORKFLOW_ID,
} from '../utils/mock_data';

describe('loadActiveWorkflowWithRetry', () => {
  const fetchError = new Error('Network timeout occurred');
  const graphQLError = (code) => ({ graphQLErrors: [{ extensions: { code } }] });

  let apollo;

  // Flushes the failed attempt's microtasks, then fires the pending retry timer.
  const runNextRetry = async () => {
    await waitForPromises();
    jest.advanceTimersByTime(THREAD_LOAD_RETRY_DELAY_MS);
    await waitForPromises();
  };

  beforeEach(() => {
    jest.useFakeTimers();
    apollo = { query: jest.fn().mockResolvedValue(MOCK_FETCH_WORKFLOW_LATEST_CHECKPOINT_RESPONSE) };
  });

  it('returns the workflow, its status and its transformed messages', async () => {
    const result = await loadActiveWorkflowWithRetry(apollo, MOCK_WORKFLOW_ID);

    expect(result).toMatchObject({
      workflow: expect.objectContaining({ id: MOCK_WORKFLOW_ID }),
      workflowStatus: 'RUNNING',
      workflowGoal: MOCK_GOAL,
    });
    expect(result.messages).toEqual([
      expect.objectContaining({ content: 'Hello', role: 'assistant' }),
    ]);
    expect(apollo.query).toHaveBeenCalledTimes(1);
  });

  it('reads the newest page of messages when paged', async () => {
    await loadActiveWorkflowWithRetry(apollo, MOCK_WORKFLOW_ID, { paged: true });

    expect(apollo.query).toHaveBeenCalledWith(
      expect.objectContaining({
        variables: { workflowId: MOCK_WORKFLOW_ID, paged: true, before: null },
      }),
    );
  });

  it('retries after the delay and resolves once an attempt succeeds', async () => {
    apollo.query
      .mockRejectedValueOnce(fetchError)
      .mockResolvedValueOnce(MOCK_FETCH_WORKFLOW_LATEST_CHECKPOINT_RESPONSE);

    const promise = loadActiveWorkflowWithRetry(apollo, MOCK_WORKFLOW_ID);
    await runNextRetry();

    await expect(promise).resolves.toMatchObject({ workflowGoal: MOCK_GOAL });
    expect(apollo.query).toHaveBeenCalledTimes(2);
  });

  it('rejects with the last error once all attempts are exhausted', async () => {
    apollo.query.mockRejectedValue(fetchError);

    const promise = loadActiveWorkflowWithRetry(apollo, MOCK_WORKFLOW_ID);
    // Prevents an unhandled rejection while the timers are advanced.
    const outcome = promise.catch((err) => err);
    await runNextRetry();
    await runNextRetry();

    expect(await outcome).toBe(fetchError);
    expect(apollo.query).toHaveBeenCalledTimes(3);
  });

  it.each(['WORKFLOW_NOT_FOUND', 'NO_RESOURCE_PERMISSIONS'])(
    'rejects a %s error without retrying',
    async (code) => {
      const terminalError = graphQLError(code);
      apollo.query.mockRejectedValue(terminalError);

      await expect(loadActiveWorkflowWithRetry(apollo, MOCK_WORKFLOW_ID)).rejects.toBe(
        terminalError,
      );
      expect(apollo.query).toHaveBeenCalledTimes(1);
    },
  );

  it('stops retrying and rejects with an abort error when the signal is aborted', async () => {
    apollo.query.mockRejectedValue(fetchError);
    const controller = new AbortController();

    const promise = loadActiveWorkflowWithRetry(apollo, MOCK_WORKFLOW_ID, {
      signal: controller.signal,
    });
    const outcome = promise.catch((err) => err);
    await waitForPromises();

    controller.abort();
    await runNextRetry();

    expect(isThreadLoadAborted(await outcome)).toBe(true);
    expect(apollo.query).toHaveBeenCalledTimes(1);
  });

  it('calls onRetry before each retry so callers can reset their loading state', async () => {
    apollo.query
      .mockRejectedValueOnce(fetchError)
      .mockResolvedValueOnce(MOCK_FETCH_WORKFLOW_LATEST_CHECKPOINT_RESPONSE);
    const onRetry = jest.fn();

    const promise = loadActiveWorkflowWithRetry(apollo, MOCK_WORKFLOW_ID, { onRetry });
    await runNextRetry();
    await promise;

    expect(onRetry).toHaveBeenCalledTimes(1);
    expect(onRetry).toHaveBeenCalledWith(fetchError);
  });
});

describe('readCheckpointMessages', () => {
  const message = { content: 'Hello', messageType: 'agent', messageId: 'msg-1' };
  const page = (pageInfo) => ({ messages: { nodes: [message], pageInfo } });

  it('reads a page of messages and the cursor of the page before it', () => {
    const result = readCheckpointMessages(page({ startCursor: 'cursor-1', hasPreviousPage: true }));

    expect(result.messages).toEqual([expect.objectContaining({ content: 'Hello', id: 'msg-1' })]);
    expect(result.olderMessagesCursor).toBe('cursor-1');
  });

  it('returns no cursor for the page holding the first message', () => {
    const result = readCheckpointMessages(
      page({ startCursor: 'cursor-0', hasPreviousPage: false }),
    );

    expect(result.olderMessagesCursor).toBeNull();
  });

  it('reads the full duoMessages list when the checkpoint was not paged', () => {
    const result = readCheckpointMessages({ duoMessages: [message] });

    expect(result.messages).toEqual([expect.objectContaining({ content: 'Hello' })]);
    expect(result.olderMessagesCursor).toBeNull();
  });
});
