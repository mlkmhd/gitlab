import {
  mountListWithQuery,
  expectListToShow,
  useFilterSpec,
  useListFixture,
  expectListRequestParams,
  lastListRequest,
} from './filter_shared_test_helpers';
import { GROUP_LIST_PATH, PROJECT_LIST_PATH, WORK_ITEMS } from './filter_test_constants';

const ALL_ITEMS = [
  WORK_ITEMS.DEPENDENT,
  WORK_ITEMS.SECOND,
  WORK_ITEMS.CHILD_TASK,
  WORK_ITEMS.BLOCKING,
  WORK_ITEMS.LINKABLE,
  WORK_ITEMS.AGENT_PLAN,
];

describe('Work items list - group namespace', () => {
  useFilterSpec();

  it('lists work items from across the group', async () => {
    useListFixture('GROUP');
    mountListWithQuery('', { isGroup: true });

    await expectListToShow(ALL_ITEMS);

    expect(lastListRequest().pathname).toBe(GROUP_LIST_PATH);
    expectListRequestParams({ include_descendants: 'true' });
    // Only project lists ask for archived items, so this also checks the list knows it is a group.
    expect(lastListRequest().searchParams.has('include_archived')).toBe(false);
  });

  it('lists only the project work items when mounted on a project', async () => {
    mountListWithQuery('');

    await expectListToShow(ALL_ITEMS);

    expect(lastListRequest().pathname).toBe(PROJECT_LIST_PATH);
  });
});
