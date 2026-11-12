import {
  mountListWithQuery,
  expectListToShow,
  useFilterSpec,
  useListFixture,
  expectListRequestParams,
} from './filter_shared_test_helpers';
import { FILTER_VALUES, WORK_ITEMS } from './filter_test_constants';

const { MILESTONE } = FILTER_VALUES;
const NO_MILESTONE_ITEMS = [
  WORK_ITEMS.SECOND,
  WORK_ITEMS.BLOCKING,
  WORK_ITEMS.LINKABLE,
  WORK_ITEMS.AGENT_PLAN,
];

describe('Work items list - milestone filter', () => {
  useFilterSpec();

  it('filters to work items in the milestone', async () => {
    useListFixture('WITH_MILESTONE');
    mountListWithQuery(`?milestone_title=${MILESTONE}`);

    await expectListToShow([WORK_ITEMS.DEPENDENT]);

    expectListRequestParams({ milestone_title: 'v1.0' });
  });

  it('filters out work items in the milestone', async () => {
    useListFixture('WITHOUT_SPECIFIC_MILESTONE');
    mountListWithQuery(`?not[milestone_title]=${MILESTONE}`);

    await expectListToShow([WORK_ITEMS.CHILD_TASK, ...NO_MILESTONE_ITEMS]);

    expectListRequestParams({ 'not[milestone_title]': 'v1.0' });
  });

  it('filters to work items with no milestone', async () => {
    useListFixture('WITH_NO_MILESTONE');
    mountListWithQuery('?milestone_title=None');

    await expectListToShow(NO_MILESTONE_ITEMS);

    expectListRequestParams({ milestone_wildcard_id: 'None' });
  });

  it('filters to work items with any milestone', async () => {
    useListFixture('WITH_ANY_MILESTONE');
    mountListWithQuery('?milestone_title=Any');

    await expectListToShow([WORK_ITEMS.DEPENDENT, WORK_ITEMS.CHILD_TASK]);

    expectListRequestParams({ milestone_wildcard_id: 'Any' });
  });

  it('filters to work items in an upcoming milestone', async () => {
    useListFixture('WITH_UPCOMING_MILESTONE');
    mountListWithQuery('?milestone_title=Upcoming');

    await expectListToShow([WORK_ITEMS.CHILD_TASK]);

    expectListRequestParams({ milestone_wildcard_id: 'Upcoming' });
  });

  it('filters to work items in a started milestone', async () => {
    useListFixture('WITH_STARTED_MILESTONE');
    mountListWithQuery('?milestone_title=Started');

    await expectListToShow([WORK_ITEMS.DEPENDENT]);

    expectListRequestParams({ milestone_wildcard_id: 'Started' });
  });
});
