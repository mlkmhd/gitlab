import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import FilteredSearchBar from '~/vue_shared/components/filtered_search_bar/filtered_search_bar_root.vue';
import { FILTERED_SEARCH_TERM } from '~/vue_shared/components/filtered_search_bar/constants';
import AutomationRecentRunsFilteredSearch from 'ee/ai/duo_agents_platform/pages/flow_triggers/index/components/automation_recent_runs_filtered_search.vue';

describe('AutomationRecentRunsFilteredSearch', () => {
  let wrapper;

  const findFilteredSearchBar = () => wrapper.findComponent(FilteredSearchBar);

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(AutomationRecentRunsFilteredSearch, {
      propsData: { filters: {}, sort: 'CREATED_DESC', ...props },
    });
  };

  it('offers the run statuses, without never run', () => {
    createComponent();

    const [statusToken, ...dateTokens] = findFilteredSearchBar().props('tokens');

    expect(statusToken.options.map(({ title }) => title)).toEqual([
      'Pending',
      'Running',
      'Awaiting input',
      'Succeeded',
      'Failed',
      'Canceled',
    ]);
    expect(dateTokens.map(({ type }) => type)).toEqual(['started-after', 'started-before']);
  });

  it('passes the filters and sort to the filtered search bar', () => {
    createComponent({
      filters: {
        status: 'FAILED',
        startedAfter: '2026-10-01',
        startedBefore: '2026-10-07',
        search: 'weekly',
      },
      sort: 'CREATED_ASC',
    });

    expect(findFilteredSearchBar().props()).toMatchObject({
      initialSortBy: 'CREATED_ASC',
      initialFilterValue: [
        { type: 'status', value: { data: 'FAILED', operator: '=' } },
        { type: 'started-after', value: { data: '2026-10-01', operator: '=' } },
        { type: 'started-before', value: { data: '2026-10-07', operator: '=' } },
        { type: FILTERED_SEARCH_TERM, value: { data: 'weekly' } },
      ],
    });
  });

  it.each`
    tokens                                                                                                                                                                                | filters
    ${[{ type: 'status', value: { data: 'FAILED', operator: '=' } }, { type: FILTERED_SEARCH_TERM, value: { data: 'weekly' } }, { type: FILTERED_SEARCH_TERM, value: { data: 'risk' } }]} | ${{ status: 'FAILED', search: 'weekly risk' }}
    ${[{ type: 'started-before', value: { data: '2026-10-07', operator: '=' } }]}                                                                                                         | ${{ startedBefore: '2026-10-07' }}
    ${[]}                                                                                                                                                                                 | ${{}}
  `('emits $filters when the bar submits', ({ tokens, filters }) => {
    createComponent();

    findFilteredSearchBar().vm.$emit('on-filter', tokens);

    expect(wrapper.emitted('filter')).toEqual([[filters]]);
  });

  it('emits the sort', () => {
    createComponent();

    findFilteredSearchBar().vm.$emit('on-sort', 'CREATED_ASC');

    expect(wrapper.emitted('sort')).toEqual([['CREATED_ASC']]);
  });
});
