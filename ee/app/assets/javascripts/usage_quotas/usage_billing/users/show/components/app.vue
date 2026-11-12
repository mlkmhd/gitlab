<script>
import {
  GlKeysetPagination,
  GlAlert,
  GlAvatar,
  GlCard,
  GlFormGroup,
  GlLoadingIcon,
} from '@gitlab/ui';
import { newDate } from '~/lib/utils/datetime/date_calculation_utility';
import { logError } from '~/lib/logger';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import HumanTimeframe from '~/vue_shared/components/datetime/human_timeframe.vue';
import { PAGE_SIZE } from '../../../constants';
import getUserSubscriptionUsageQuery from '../graphql/get_user_subscription_usage.query.graphql';
import getUserSubscriptionUsageEvents from '../graphql/get_user_subscription_usage_events.query.graphql';
import { fillUsageValues, formatNumber } from '../../../utils';
import { processFlowTypes } from '../utils';
import DateRangeFilter from '../../../../wallet_agnostic_credits_dashboard/shared/components/date_range_filter.vue';
import {
  THIS_MONTH,
  LAST_MONTH,
  LAST_7_DAYS,
  LAST_30_DAYS,
  CUSTOM,
  MAX_DATE_RANGE_IN_DAYS,
} from '../../../../wallet_agnostic_credits_dashboard/shared/components/constants';
import {
  availableDateRangeOptions,
  getTodayLocal,
  initialDateRangeOption,
} from '../../../../wallet_agnostic_credits_dashboard/shared/components/utils';
import EventsTable from './events_table.vue';
import FlowTypeFilter from './flow_type_filter.vue';

const DATE_RANGE_OPTIONS = [THIS_MONTH, LAST_MONTH, LAST_7_DAYS, LAST_30_DAYS, CUSTOM];

export default {
  name: 'UsageBillingUserDashboardApp',
  components: {
    GlCard,
    GlFormGroup,
    GlLoadingIcon,
    GlAlert,
    GlAvatar,
    GlKeysetPagination,
    DateRangeFilter,
    HumanTimeframe,
    EventsTable,
    FlowTypeFilter,
  },
  MAX_DATE_RANGE_IN_DAYS,
  inject: {
    username: 'username',
    namespacePath: {
      default: null,
    },
    subscriptionStartDate: {
      default: null,
    },
  },
  data() {
    return {
      isUsageLoadingError: false,
      isEventsLoadingError: false,
      subscriptionUsage: null,
      userEvents: null,
      pagination: {
        after: null,
        before: null,
        first: PAGE_SIZE,
        last: null,
      },
      appliedFlowTypes: null,
      selectedDateRange: { ...initialDateRangeOption(THIS_MONTH, this.subscriptionStartDate) },
      todayLocal: getTodayLocal(),
    };
  },
  apollo: {
    subscriptionUsage: {
      query: getUserSubscriptionUsageQuery,
      variables() {
        return {
          // Note: namespacePath will be present on SaaS only, indicating a root group.
          // SM would pass null in this variable, requesting instance-level data.
          namespacePath: this.namespacePath,
          username: this.username,
          startDate: this.selectedDateRange.startDate,
          endDate: this.selectedDateRange.endDate,
        };
      },
      error(error) {
        this.isUsageLoadingError = true;
        logError(error);
        captureException(error);
      },
      update(data) {
        return data.subscriptionUsage;
      },
      result({ error }) {
        if (!error) {
          this.isUsageLoadingError = false;
        }
      },
    },
    userEvents: {
      query: getUserSubscriptionUsageEvents,
      variables() {
        return {
          namespacePath: this.namespacePath,
          username: this.username,
          flowTypes: this.appliedFlowTypes,
          startDate: this.selectedDateRange.startDate,
          endDate: this.selectedDateRange.endDate,

          first: this.pagination.first,
          last: this.pagination.last,
          after: this.pagination.after,
          before: this.pagination.before,
        };
      },
      error(error) {
        this.isEventsLoadingError = true;
        logError(error);
        captureException(error);
      },
      update(data) {
        return data.subscriptionUsage.usersUsage.users.nodes[0];
      },
      result({ error }) {
        if (!error) {
          this.isEventsLoadingError = false;
        }
      },
    },
  },
  computed: {
    dateRangeOptions() {
      return availableDateRangeOptions(DATE_RANGE_OPTIONS, this.subscriptionStartDate);
    },
    // Local-midnight date so the picker, which compares local calendar parts,
    // reads the same calendar day the subscription started on.
    subscriptionStartDateLocal() {
      return this.subscriptionStartDate ? newDate(this.subscriptionStartDate) : null;
    },
    isUsageLoading() {
      return this.$apollo.queries.subscriptionUsage.loading;
    },
    // Refetches keep the previous result, so only the first load blanks the page.
    isUsageInitialLoading() {
      return this.isUsageLoading && !this.subscriptionUsage;
    },
    isUsageBillingDisabled() {
      return this.subscriptionUsage?.enabled === false;
    },
    user() {
      return this.subscriptionUsage?.usersUsage?.users?.nodes?.[0];
    },
    usage() {
      return fillUsageValues(this.user?.usage);
    },
    // The API's `totalCreditsUsed` is billable only; the card adds the non-billable
    // credits so it matches the user's row in Usage by user.
    creditsUsedIncludingNonBillable() {
      return this.usage.totalCreditsUsed + this.usage.nonBillableCreditsUsed;
    },
    events() {
      return this.userEvents?.events?.nodes ?? [];
    },
    pageInfo() {
      return this.userEvents?.events?.pageInfo;
    },
    usedFlowTypes() {
      const rawFlowTypes = this.user?.usedFlowTypes ?? [];

      return processFlowTypes(rawFlowTypes);
    },
    appliedFlowTypesWithFallback() {
      // When `appliedFlowTypes == null`, it means all options are selected
      if (this.appliedFlowTypes === null) {
        return this.usedFlowTypes.map((x) => x.value);
      }

      return this.appliedFlowTypes;
    },
  },
  methods: {
    formatNumber,
    onNextPage(item) {
      this.pagination = {
        first: PAGE_SIZE,
        after: item,
        last: null,
        before: null,
      };
    },
    onPrevPage(item) {
      this.pagination = {
        first: null,
        after: null,
        last: PAGE_SIZE,
        before: item,
      };
    },
    resetPagination() {
      this.pagination = {
        after: null,
        before: null,
        first: PAGE_SIZE,
        last: null,
      };
    },
    onFilterApply(selectedEventTypes) {
      // First query is fired with null value, indicating that this filter is not applied.
      // When all flow types are selected — we reset the selection list to null, to use cache from
      // the first query
      const areAllFlowTypesSelected = selectedEventTypes.length === this.usedFlowTypes.length;
      this.appliedFlowTypes = areAllFlowTypesSelected ? null : [...selectedEventTypes];
      this.resetPagination();
    },
    onDateRangeChange(dateRange) {
      // The new range may not include the selected flow types, so show all of them again.
      this.appliedFlowTypes = null;
      this.selectedDateRange = dateRange;
      this.resetPagination();
    },
  },
};
</script>
<template>
  <section>
    <div v-if="isUsageInitialLoading">
      <gl-loading-icon />
    </div>

    <gl-alert
      v-else-if="isUsageBillingDisabled"
      data-testid="usage-billing-disabled-alert"
      variant="warning"
      class="gl-my-3"
      :dismissible="false"
    >
      {{ s__('UsageBilling|Usage Billing is disabled') }}
    </gl-alert>

    <template v-else>
      <gl-alert v-if="isUsageLoadingError" variant="danger" class="gl-my-3">
        {{ s__('UsageBilling|An error occurred while fetching usage data') }}
      </gl-alert>

      <template v-else>
        <header
          class="gl-my-5 gl-flex gl-flex-col gl-gap-3"
          data-testid="usage-billing-user-header"
        >
          <div
            class="gl-mb-2 gl-flex gl-flex-col gl-items-start gl-justify-between gl-gap-3 @md/panel:gl-flex-row"
          >
            <div class="gl-flex gl-items-center">
              <gl-avatar
                :title="user.name"
                :alt="user.name"
                :src="user.avatarUrl"
                :entity-name="user.name"
                :size="64"
                class="gl-mr-3"
              />

              <div>
                <h1 class="gl-heading-1 gl-my-0">{{ user.name }}</h1>
                <p class="gl-my-0 gl-font-bold gl-text-subtle">@{{ user.username }}</p>
              </div>
            </div>
          </div>
        </header>

        <div
          class="gl-my-5 gl-flex gl-flex-col gl-gap-5 @md/panel:gl-flex-row"
          data-testid="usage-billing-user-cards-row"
        >
          <gl-card
            data-testid="total-usage-card"
            class="gl-max-w-1/2 gl-flex-1"
            body-class="gl-p-4"
          >
            <div class="gl-heading-scale-600 gl-mb-3 gl-font-bold">
              <gl-loading-icon v-if="isUsageLoading" size="lg" inline />
              <template v-else>{{ formatNumber(creditsUsedIncludingNonBillable) }}</template>
            </div>
            <div class="gl-font-bold">
              <p class="gl-my-0">{{ s__('UsageBillingUserDetails|Total credits used') }}</p>
              <p class="gl-my-0 gl-text-sm gl-text-subtle">
                <human-timeframe
                  :from="selectedDateRange.startDate"
                  :till="selectedDateRange.endDate"
                />
              </p>
            </div>
          </gl-card>
        </div>
      </template>

      <section data-testid="usage-billing-user-events-list">
        <div class="gl-mb-4 gl-flex gl-gap-7">
          <gl-form-group :label="s__('UsageBilling|Date range')" class="gl-m-0">
            <date-range-filter
              :value="selectedDateRange"
              :options="dateRangeOptions"
              :custom-date-range-limit="$options.MAX_DATE_RANGE_IN_DAYS"
              :custom-date-range-max-date="todayLocal"
              :custom-date-range-min-date="subscriptionStartDateLocal"
              @input="onDateRangeChange"
            />
          </gl-form-group>
          <flow-type-filter
            :flow-types="usedFlowTypes"
            :applied-flow-types="appliedFlowTypesWithFallback"
            :loading="isUsageLoading"
            @apply="onFilterApply"
          />
        </div>

        <gl-alert v-if="isEventsLoadingError" variant="danger" class="gl-my-3">
          {{ s__('UsageBilling|An error occurred while fetching events list') }}
        </gl-alert>

        <div v-else-if="$apollo.queries.userEvents.loading">
          <gl-loading-icon />
        </div>

        <events-table v-else :events="events" />

        <div v-if="pageInfo" class="gl-mt-5 gl-flex gl-justify-center">
          <gl-keyset-pagination v-bind="pageInfo" @prev="onPrevPage" @next="onNextPage" />
        </div>
      </section>
    </template>
  </section>
</template>
