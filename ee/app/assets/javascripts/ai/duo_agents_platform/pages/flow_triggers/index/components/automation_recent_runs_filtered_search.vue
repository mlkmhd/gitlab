<script>
import { GlFilteredSearchToken } from '@gitlab/ui';
import { __, s__ } from '~/locale';
import FilteredSearchBar from '~/vue_shared/components/filtered_search_bar/filtered_search_bar_root.vue';
import {
  FILTERED_SEARCH_TERM,
  OPERATORS_IS,
} from '~/vue_shared/components/filtered_search_bar/constants';
import {
  prepareTokens,
  processFilters,
} from '~/vue_shared/components/filtered_search_bar/filtered_search_utils';
import DateToken from '~/vue_shared/components/filtered_search_bar/tokens/date_token.vue';
import {
  AUTOMATION_RUN_STATUS_META,
  AUTOMATION_RUN_STATUS_NEVER,
} from 'ee/ai/duo_agents_platform/constants';

const filtersToTokens = ({ status, startedAfter, startedBefore, search }) =>
  prepareTokens({
    status: status && { value: status, operator: '=' },
    'started-after': startedAfter && { value: startedAfter, operator: '=' },
    'started-before': startedBefore && { value: startedBefore, operator: '=' },
    [FILTERED_SEARCH_TERM]: search && { value: search },
  });

const tokensToFilters = (tokens) => {
  const {
    status: [status] = [],
    'started-after': [startedAfter] = [],
    'started-before': [startedBefore] = [],
    [FILTERED_SEARCH_TERM]: searchTerms = [],
  } = processFilters(tokens);

  const search = searchTerms
    .map(({ value }) => value)
    .join(' ')
    .trim();

  return {
    ...(status?.value && { status: status.value }),
    ...(startedAfter?.value && { startedAfter: startedAfter.value }),
    ...(startedBefore?.value && { startedBefore: startedBefore.value }),
    ...(search && { search }),
  };
};

export default {
  name: 'AutomationRecentRunsFilteredSearch',
  components: {
    FilteredSearchBar,
  },
  props: {
    filters: {
      type: Object,
      required: true,
    },
    sort: {
      type: String,
      required: true,
    },
  },
  emits: ['filter', 'sort'],
  computed: {
    initialFilterValue() {
      return filtersToTokens(this.filters);
    },
  },
  methods: {
    handleFilter(tokens) {
      this.$emit('filter', tokensToFilters(tokens));
    },
  },
  tokens: [
    {
      type: 'status',
      title: __('Status'),
      icon: 'status',
      token: GlFilteredSearchToken,
      operators: OPERATORS_IS,
      unique: true,
      options: Object.entries(AUTOMATION_RUN_STATUS_META)
        .filter(([status]) => status !== AUTOMATION_RUN_STATUS_NEVER)
        .map(([status, { text }]) => ({ value: status, title: text })),
    },
    {
      type: 'started-after',
      title: s__('DuoAgentsPlatform|Started after'),
      icon: 'calendar',
      token: DateToken,
      operators: OPERATORS_IS,
      unique: true,
    },
    {
      type: 'started-before',
      title: s__('DuoAgentsPlatform|Started before'),
      icon: 'calendar',
      token: DateToken,
      operators: OPERATORS_IS,
      unique: true,
    },
  ],
  sortOptions: [
    {
      id: 1,
      title: __('Started'),
      sortDirection: { descending: 'CREATED_DESC', ascending: 'CREATED_ASC' },
    },
  ],
};
</script>

<template>
  <filtered-search-bar
    namespace="duo-agents-platform-automation-runs"
    :tokens="$options.tokens"
    :search-input-placeholder="s__('DuoAgentsPlatform|Search runs')"
    :sort-options="$options.sortOptions"
    :initial-filter-value="initialFilterValue"
    :initial-sort-by="sort"
    sync-filter-and-sort
    terms-as-tokens
    class="gl-p-0"
    @on-filter="handleFilter"
    @on-sort="$emit('sort', $event)"
  />
</template>
