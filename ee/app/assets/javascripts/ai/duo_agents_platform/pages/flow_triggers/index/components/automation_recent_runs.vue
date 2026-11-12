<script>
import {
  GlAlert,
  GlBadge,
  GlButton,
  GlKeysetPagination,
  GlSkeletonLoader,
  GlTableLite,
} from '@gitlab/ui';
import { fetchPolicies } from '~/lib/graphql';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { nDaysAfter, newDate } from '~/lib/utils/datetime/date_calculation_utility';
import { timeIntervalInWords } from '~/lib/utils/datetime/date_format_utility';
import { __ } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import ViewSessionButton from 'ee/ai/shared/widgets/view_session_button.vue';
import getAutomationRecentRuns from 'ee/ai/duo_agents_platform/graphql/queries/get_automation_recent_runs.query.graphql';
import {
  AUTOMATION_RUN_STATUS_META,
  DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES,
  DUO_AGENT_PLATFORM_POLLING_INTERVAL,
  WORKFLOW_STATUS_TO_AUTOMATION_RUN_STATUS,
  WORKFLOW_TERMINAL_STATUSES,
} from 'ee/ai/duo_agents_platform/constants';
import AutomationRecentRunsFilteredSearch from './automation_recent_runs_filtered_search.vue';

const { first: PAGE_SIZE } = DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES;
const POLLING_STATUSES = ['CREATED', 'RUNNING'];
const DEFAULT_SORT = 'CREATED_DESC';

export default {
  name: 'AutomationRecentRuns',
  components: {
    AutomationRecentRunsFilteredSearch,
    GlAlert,
    GlBadge,
    GlButton,
    GlKeysetPagination,
    GlSkeletonLoader,
    GlTableLite,
    TimeAgoTooltip,
    ViewSessionButton,
  },
  inject: ['projectPath'],
  props: {
    automationId: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      sessions: null,
      paginationVariables: { ...DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES },
      filters: {},
      sort: DEFAULT_SORT,
      hasError: false,
    };
  },
  apollo: {
    sessions: {
      query: getAutomationRecentRuns,
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      variables() {
        return {
          projectPath: this.projectPath,
          id: this.automationId,
          ...this.paginationVariables,
          ...this.filterVariables,
        };
      },
      update: (data) =>
        data.project?.aiFlowTriggers?.nodes[0]?.sessions ?? { nodes: [], pageInfo: {} },
      result({ error }) {
        if (!error) this.hasError = false;
        // A reactive pollInterval() is not applied again when the variables change,
        // so a new page would poll without a delay.
        if (this.sessions?.nodes.some(({ status }) => POLLING_STATUSES.includes(status))) {
          this.$apollo.queries.sessions.startPolling(DUO_AGENT_PLATFORM_POLLING_INTERVAL);
        } else {
          this.$apollo.queries.sessions.stopPolling();
        }
      },
      error(error) {
        this.hasError = true;
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    hasActiveFilters() {
      return Object.keys(this.filters).length > 0;
    },
    filterVariables() {
      const { status, search, startedAfter, startedBefore } = this.filters;

      return {
        statuses: status
          ? Object.keys(WORKFLOW_STATUS_TO_AUTOMATION_RUN_STATUS).filter(
              (workflowStatus) =>
                WORKFLOW_STATUS_TO_AUTOMATION_RUN_STATUS[workflowStatus] === status,
            )
          : null,
        search: search ?? null,
        createdAfter: startedAfter ? newDate(startedAfter).toISOString() : null,
        createdBefore: startedBefore ? nDaysAfter(newDate(startedBefore), 1).toISOString() : null,
        sort: this.sort === DEFAULT_SORT ? null : this.sort,
      };
    },
    runs() {
      return (this.sessions?.nodes ?? []).map(({ id, status, createdAt, updatedAt }) => ({
        sessionId: getIdFromGraphQLId(id),
        status: AUTOMATION_RUN_STATUS_META[WORKFLOW_STATUS_TO_AUTOMATION_RUN_STATUS[status]],
        createdAt,
        duration: WORKFLOW_TERMINAL_STATUSES.includes(status)
          ? timeIntervalInWords((new Date(updatedAt) - new Date(createdAt)) / 1000, {
              abbreviated: true,
            })
          : null,
      }));
    },
  },
  methods: {
    setFilters(filters) {
      this.filters = filters;
      this.paginationVariables = { ...DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES };
    },
    setSort(sort) {
      this.sort = sort;
      this.paginationVariables = { ...DEFAULT_AGENT_PLATFORM_PAGINATION_VARIABLES };
    },
    nextPage() {
      this.paginationVariables = {
        first: PAGE_SIZE,
        after: this.sessions.pageInfo.endCursor,
        last: null,
        before: null,
      };
      this.scrollToHeading();
    },
    prevPage() {
      this.paginationVariables = {
        first: null,
        after: null,
        last: PAGE_SIZE,
        before: this.sessions.pageInfo.startCursor,
      };
      this.scrollToHeading();
    },
    scrollToHeading() {
      this.$refs.heading.scrollIntoView({ block: 'start' });
    },
  },
  fields: [
    { key: 'status', label: __('Status') },
    { key: 'createdAt', label: __('Started') },
    { key: 'duration', label: __('Duration') },
    { key: 'session', label: __('Actions'), thClass: 'gl-w-0', tdClass: 'gl-text-right' },
  ],
  emptyValue: '\u2014',
};
</script>

<template>
  <section>
    <h3 ref="heading" class="gl-heading-4 gl-mb-3">{{ s__('DuoAgentsPlatform|Recent runs') }}</h3>
    <automation-recent-runs-filtered-search
      v-if="sessions && (runs.length || hasActiveFilters)"
      :filters="filters"
      :sort="sort"
      class="gl-mb-3"
      @filter="setFilters"
      @sort="setSort"
    />
    <gl-alert v-if="hasError" variant="danger" :dismissible="false" class="gl-mb-3">
      {{ s__('DuoAgentsPlatform|Failed to load recent runs.') }}
    </gl-alert>
    <gl-skeleton-loader v-if="!sessions && !hasError" :lines="3" />
    <gl-table-lite v-else-if="runs.length" :items="runs" :fields="$options.fields" stacked="sm">
      <template #head(session)="{ label }">
        <span class="gl-sr-only">{{ label }}</span>
      </template>
      <template #cell(status)="{ item }">
        <gl-badge
          v-if="item.status"
          :variant="item.status.variant"
          :icon="item.status.icon"
          icon-size="sm"
        >
          {{ item.status.text }}
        </gl-badge>
      </template>
      <template #cell(createdAt)="{ item }">
        <time-ago-tooltip :time="item.createdAt" />
      </template>
      <template #cell(duration)="{ item }">
        {{ item.duration || $options.emptyValue }}
      </template>
      <template #cell(session)="{ item }">
        <view-session-button
          :session-id="item.sessionId"
          size="small"
          class="gl-whitespace-nowrap"
        />
      </template>
    </gl-table-lite>
    <div
      v-else-if="sessions && hasActiveFilters"
      class="gl-flex gl-flex-col gl-items-start gl-gap-2"
    >
      <p class="gl-m-0 gl-text-subtle">
        {{ s__('DuoAgentsPlatform|No runs match these filters.') }}
      </p>
      <gl-button category="tertiary" data-testid="clear-filters" @click="setFilters({})">
        {{ __('Clear filters') }}
      </gl-button>
    </div>
    <p v-else-if="sessions" class="gl-m-0 gl-text-subtle">
      {{ s__('DuoAgentsPlatform|No runs yet.') }}
    </p>
    <gl-keyset-pagination
      v-if="sessions"
      v-bind="sessions.pageInfo"
      class="gl-mt-6 gl-flex gl-justify-center"
      @next="nextPage"
      @prev="prevPage"
    />
  </section>
</template>
