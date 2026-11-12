import {
  mountListWithQuery,
  expectListToShow,
  expectTokensToShow,
  useFilterSpec,
  useListFixture,
  expectListRequestParams,
} from './filter_shared_test_helpers';
import { WORK_ITEMS } from './filter_test_constants';

const CONFIDENTIAL_ITEM = WORK_ITEMS.BLOCKING;
const PUBLIC_ITEMS = [
  WORK_ITEMS.DEPENDENT,
  WORK_ITEMS.SECOND,
  WORK_ITEMS.CHILD_TASK,
  WORK_ITEMS.LINKABLE,
  WORK_ITEMS.AGENT_PLAN,
];

describe('Work items list - confidential filter', () => {
  useFilterSpec();

  it('filters to confidential work items', async () => {
    useListFixture('CONFIDENTIAL');
    mountListWithQuery('?confidential=yes');

    await expectListToShow([CONFIDENTIAL_ITEM]);
    await expectTokensToShow(['Confidential is Yes', 'State is Open']);

    expectListRequestParams({ confidential: 'true' });
  });

  it('filters to non-confidential work items', async () => {
    useListFixture('NOT_CONFIDENTIAL');
    mountListWithQuery('?confidential=no');

    await expectListToShow(PUBLIC_ITEMS);

    expectListRequestParams({ confidential: 'false' });
  });
});
