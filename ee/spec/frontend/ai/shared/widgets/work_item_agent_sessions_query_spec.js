import getDuoAgentSessionsOnWorkItemQuery from 'ee/ai/shared/widgets/graphql/get_duo_agent_sessions_on_work_item.query.graphql';
import { AGENT_SESSIONS_PAGE_SIZE } from 'ee/ai/shared/widgets/constants';
import {
  workItemAgentSessionsQueryOptions,
  workItemAgentSessionsVariables,
} from 'ee/ai/shared/widgets/work_item_agent_sessions_query';

describe('work item agent sessions query', () => {
  const workItemId = 'gid://gitlab/WorkItem/1';

  describe('workItemAgentSessionsVariables', () => {
    it('returns the work item ID and the page size', () => {
      expect(workItemAgentSessionsVariables(workItemId)).toEqual({
        id: workItemId,
        first: AGENT_SESSIONS_PAGE_SIZE,
      });
    });
  });

  describe('workItemAgentSessionsQueryOptions', () => {
    const options = workItemAgentSessionsQueryOptions();

    it('uses the sessions query', () => {
      expect(options.query).toBe(getDuoAgentSessionsOnWorkItemQuery);
    });

    it('builds the variables from the workItemId of the component', () => {
      expect(options.variables.call({ workItemId })).toEqual(
        workItemAgentSessionsVariables(workItemId),
      );
    });

    describe('when the response has sessions', () => {
      it('returns the sessions', () => {
        const nodes = [{ id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1' }];

        expect(
          options.update({ workItem: { features: { aiSession: { duoWorkflows: { nodes } } } } }),
        ).toBe(nodes);
      });
    });

    describe('when the response has no sessions', () => {
      it('returns an empty array', () => {
        expect(options.update({ workItem: null })).toEqual([]);
      });
    });
  });
});
