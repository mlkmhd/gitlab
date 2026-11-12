<script>
import { GlSkeletonLoader, GlTooltipDirective, GlLink } from '@gitlab/ui';
import { GlSingleStat } from '@gitlab/ui/src/charts';
import Api from 'ee/api';
import { createAlert } from '~/alert';
import { sprintf, __, s__ } from '~/locale';
import Tracking, { InternalEvents } from '~/tracking';

const MERGE_REQUESTS_TRACKING_LABEL = 'g_analytics_activity_widget_mr_created_clicked';
const ISSUES_TRACKING_LABEL = 'g_analytics_activity_widget_issues_created_clicked';
const NEW_MEMBERS_TRACKING_LABEL = 'g_analytics_activity_widget_members_added_clicked';
const ACTIVITY_COUNT_LIMIT = 999;
const UNKNOWN_COUNT = '—';

export default {
  name: 'GroupActivityCard',
  components: {
    GlSkeletonLoader,
    GlSingleStat,
    GlLink,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [Tracking.mixin(), InternalEvents.mixin()],
  inject: [
    'canReadBilling',
    'showPlanIndicator',
    'groupBillingsPath',
    'groupSubscriptionPlanName',
    'groupFullPath',
    'mergeRequestsMetricLink',
    'issuesMetricLink',
    'newMembersMetricLink',
  ],
  data() {
    return {
      isLoading: false,
      metrics: {
        mergeRequests: {
          value: null,
          tooLarge: false,
          label: s__('GroupActivityMetrics|Merge requests created'),
          link: this.mergeRequestsMetricLink,
          trackingLabel: MERGE_REQUESTS_TRACKING_LABEL,
        },
        issues: {
          value: null,
          tooLarge: false,
          label: s__('GroupActivityMetrics|Issues created'),
          link: this.issuesMetricLink,
          trackingLabel: ISSUES_TRACKING_LABEL,
        },
        newMembers: {
          value: null,
          tooLarge: false,
          label: s__('GroupActivityMetrics|Members added'),
          link: this.newMembersMetricLink,
          trackingLabel: NEW_MEMBERS_TRACKING_LABEL,
        },
      },
    };
  },
  computed: {
    metricsArray() {
      return Object.entries(this.metrics).map(([key, obj]) => {
        const { value, tooLarge, label, link, trackingLabel } = obj;
        return {
          key,
          value,
          tooLarge,
          label,
          link,
          trackingLabel,
        };
      });
    },
  },
  created() {
    this.fetchMetrics(this.groupFullPath);
  },
  methods: {
    fetchMetrics(groupPath) {
      this.isLoading = true;

      return Promise.all([
        Api.groupActivityMergeRequestsCount(groupPath),
        Api.groupActivityIssuesCount(groupPath),
        Api.groupActivityNewMembersCount(groupPath),
      ])
        .then(([mrResponse, issuesResponse, newMembersResponse]) => {
          this.metrics.mergeRequests.value = mrResponse.data.merge_requests_count;
          this.metrics.mergeRequests.tooLarge = Boolean(mrResponse.data.too_large);
          this.metrics.issues.value = issuesResponse.data.issues_count;
          this.metrics.issues.tooLarge = Boolean(issuesResponse.data.too_large);
          this.metrics.newMembers.value = newMembersResponse.data.new_members_count;
          this.metrics.newMembers.tooLarge = Boolean(newMembersResponse.data.too_large);
          this.isLoading = false;
        })
        .catch(() => {
          createAlert({
            message: __('Failed to load group activity metrics. Please try again.'),
          });
          this.isLoading = false;
        });
    },
    clampValue(value, tooLarge) {
      if (tooLarge) return UNKNOWN_COUNT;

      return value > ACTIVITY_COUNT_LIMIT ? '999+' : `${value}`;
    },
    tooltip(value, tooLarge) {
      if (tooLarge) return s__('GroupActivityMetrics|This count took too long to calculate');

      return value > ACTIVITY_COUNT_LIMIT ? __('Results limit reached') : null;
    },
    clickMetric(trackingLabel) {
      this.track('click_button', { label: trackingLabel });
    },
    handlePlanIndicatorClick() {
      this.trackEvent('click_plan_indicator_on_group_overview_page');
    },
  },
  activityTimeSpan: sprintf(__('Last %{days} days'), { days: 30 }),
};
</script>

<template>
  <div class="gl-mb-4 gl-mt-6 gl-flex gl-flex-row gl-flex-wrap gl-items-start">
    <div class="gl-mb-4 gl-flex gl-shrink-0 gl-flex-col gl-pr-9">
      <gl-single-stat
        :value="$options.activityTimeSpan"
        :title="s__('GroupActivityMetrics|Recent activity')"
        :should-animate="true"
      />
    </div>
    <div v-if="showPlanIndicator" class="gl-mb-4 gl-flex gl-shrink-0 gl-flex-col gl-pr-9">
      <gl-link
        v-if="canReadBilling"
        :href="groupBillingsPath"
        data-testid="subscription-stat-link"
        class="!gl-no-underline hover:gl-bg-strong"
        @click.stop="handlePlanIndicatorClick"
      >
        <gl-single-stat
          :value="groupSubscriptionPlanName"
          :title="s__('GroupActivityMetrics|Subscription')"
          meta-icon="chevron-right"
          :should-animate="true"
        />
      </gl-link>
      <gl-single-stat
        v-else
        data-testid="subscription-stat-info"
        :value="groupSubscriptionPlanName"
        :title="s__('GroupActivityMetrics|Subscription')"
        :should-animate="true"
      />
    </div>
    <div
      v-for="{ key, value, tooLarge, label, link, trackingLabel } in metricsArray"
      :key="key"
      class="gl-mb-4 gl-pr-9"
    >
      <gl-skeleton-loader v-if="isLoading" />
      <a
        v-else
        v-gl-tooltip="tooltip(value, tooLarge)"
        :href="link"
        class="gl-block gl-rounded-base !gl-no-underline hover:gl-bg-strong"
        data-testid="single-stat-link"
        @click="clickMetric(trackingLabel)"
      >
        <gl-single-stat
          :value="clampValue(value, tooLarge)"
          :title="label"
          :should-animate="true"
        />
      </a>
    </div>
  </div>
</template>
