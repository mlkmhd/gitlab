import { FLOW_ACTION_TIMEOUT_MS } from './constants';

// The Plan button unmounts once planning is enabled, before the workplan widget mounts,
// so it leaves the request to start the run here for the widget to pick up.
const requests = new Map();

export const requestWorkplanStart = (workItemId) => {
  requests.set(workItemId, Date.now());
};

export const cancelWorkplanStartRequest = (workItemId) => {
  requests.delete(workItemId);
};

// Returns true once per request, and never for one older than the action watchdog, so a
// request whose widget never mounted can't start a run later.
export const consumeWorkplanStartRequest = (workItemId) => {
  const requestedAt = requests.get(workItemId);
  requests.delete(workItemId);
  return requestedAt !== undefined && Date.now() - requestedAt < FLOW_ACTION_TIMEOUT_MS;
};
