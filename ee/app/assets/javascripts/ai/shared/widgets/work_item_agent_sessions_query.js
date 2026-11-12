import getDuoAgentSessionsOnWorkItemQuery from './graphql/get_duo_agent_sessions_on_work_item.query.graphql';
import { AGENT_SESSIONS_PAGE_SIZE } from './constants';

export const workItemAgentSessionsVariables = (workItemId) => ({
  id: workItemId,
  first: AGENT_SESSIONS_PAGE_SIZE,
});

// The Sessions widget and the Implementation widget must share these options, so they send
// one request and read one cache entry. Expects a `workItemId` prop on the component.
export const workItemAgentSessionsQueryOptions = () => ({
  query: getDuoAgentSessionsOnWorkItemQuery,
  variables() {
    return workItemAgentSessionsVariables(this.workItemId);
  },
  update(data) {
    return data?.workItem?.features?.aiSession?.duoWorkflows?.nodes ?? [];
  },
});
