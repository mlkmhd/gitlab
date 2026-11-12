import { FLOW_ACTION_TIMEOUT_MS } from 'ee/work_items/components/implementation_widget/constants';
import {
  cancelWorkplanStartRequest,
  consumeWorkplanStartRequest,
  requestWorkplanStart,
} from 'ee/work_items/components/implementation_widget/workplan_start_request';

describe('workplan start request', () => {
  const workItemId = 'gid://gitlab/WorkItem/1';

  let now;

  const advance = (ms) => {
    now += ms;
  };

  beforeEach(() => {
    now = 1000;
    jest.spyOn(Date, 'now').mockImplementation(() => now);
    cancelWorkplanStartRequest(workItemId);
  });

  it('is not consumable before it is requested', () => {
    expect(consumeWorkplanStartRequest(workItemId)).toBe(false);
  });

  it('is consumable once', () => {
    requestWorkplanStart(workItemId);

    expect(consumeWorkplanStartRequest(workItemId)).toBe(true);
    expect(consumeWorkplanStartRequest(workItemId)).toBe(false);
  });

  it('is scoped to the work item', () => {
    requestWorkplanStart(workItemId);

    expect(consumeWorkplanStartRequest('gid://gitlab/WorkItem/2')).toBe(false);
    expect(consumeWorkplanStartRequest(workItemId)).toBe(true);
  });

  it('is not consumable once cancelled', () => {
    requestWorkplanStart(workItemId);
    cancelWorkplanStartRequest(workItemId);

    expect(consumeWorkplanStartRequest(workItemId)).toBe(false);
  });

  it('is still consumable just before it expires', () => {
    requestWorkplanStart(workItemId);
    advance(FLOW_ACTION_TIMEOUT_MS - 1);

    expect(consumeWorkplanStartRequest(workItemId)).toBe(true);
  });

  it('expires, so a widget that never mounted cannot start a run later', () => {
    requestWorkplanStart(workItemId);
    advance(FLOW_ACTION_TIMEOUT_MS);

    expect(consumeWorkplanStartRequest(workItemId)).toBe(false);
  });
});
