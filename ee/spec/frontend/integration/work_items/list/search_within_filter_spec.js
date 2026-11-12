import {
  mountListWithQuery,
  expectListToShow,
  expectTokensToShow,
  useFilterSpec,
  useListFixture,
  expectListRequestParams,
} from './filter_shared_test_helpers';
import { WORK_ITEMS } from './filter_test_constants';

describe('Work items list - search within filter', () => {
  useFilterSpec();

  it('searches titles only', async () => {
    useListFixture('MATCHING_TITLE');
    mountListWithQuery('?search=Dependent&in=TITLE');

    await expectListToShow([WORK_ITEMS.DEPENDENT]);
    await expectTokensToShow(['Search within is Titles', 'State is Open']);

    expectListRequestParams({ search: 'Dependent', in: 'title' });
  });

  it('searches descriptions only', async () => {
    useListFixture('MATCHING_DESCRIPTION');
    mountListWithQuery('?search=searchable&in=DESCRIPTION');

    await expectListToShow([WORK_ITEMS.BLOCKING]);

    expectListRequestParams({ search: 'searchable', in: 'description' });
  });
});
