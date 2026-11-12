import {
  mountListWithQuery,
  expectListToShow,
  useFilterSpec,
  useListFixture,
  expectListRequestParams,
} from './filter_shared_test_helpers';
import { FILTER_VALUES, WORK_ITEMS } from './filter_test_constants';

const { ASSIGNABLE_USER: AUTHOR, SECOND_ASSIGNABLE_USER: SECOND_AUTHOR } = FILTER_VALUES;

describe('Work items list - author filter', () => {
  useFilterSpec();

  it('filters to work items created by the author', async () => {
    useListFixture('WITH_AUTHOR');
    mountListWithQuery(`?author_username=${AUTHOR}`);

    await expectListToShow([WORK_ITEMS.LINKABLE]);

    expectListRequestParams({ author_username: 'assignable_user' });
  });

  it('filters out work items created by the author', async () => {
    useListFixture('WITHOUT_AUTHOR');
    mountListWithQuery(`?not[author_username][]=${AUTHOR}`);

    await expectListToShow([
      WORK_ITEMS.DEPENDENT,
      WORK_ITEMS.SECOND,
      WORK_ITEMS.CHILD_TASK,
      WORK_ITEMS.BLOCKING,
      WORK_ITEMS.AGENT_PLAN,
    ]);

    expectListRequestParams({ 'not[author_username][]': 'assignable_user' });
  });

  it('filters to work items created by one of several authors', async () => {
    useListFixture('WITH_ANY_OF_AUTHORS');
    mountListWithQuery(`?or[author_username][]=${AUTHOR}&or[author_username][]=${SECOND_AUTHOR}`);

    await expectListToShow([WORK_ITEMS.CHILD_TASK, WORK_ITEMS.LINKABLE]);

    expectListRequestParams({
      'or[author_usernames][]': ['assignable_user', 'second_assignable_user'],
    });
  });
});
