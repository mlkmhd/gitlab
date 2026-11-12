<script>
import { GlButton } from '@gitlab/ui';
import UserGroupCalloutDismisser from '~/vue_shared/components/user_group_callout_dismisser.vue';
import { InternalEvents } from '~/tracking';
import axios from '~/lib/utils/axios_utils';
import { formatNumber, s__, sprintf } from '~/locale';
import {
  POST_TRIAL_USAGE_COMPUTE_MINUTES_THRESHOLD,
  POST_TRIAL_USAGE_CREDITS_THRESHOLD,
  POST_TRIAL_USAGE_SEATS_THRESHOLD,
} from 'ee/billings/constants';

export default {
  name: 'PostTrialUsageCard',
  components: {
    GlButton,
    UserGroupCalloutDismisser,
  },
  mixins: [InternalEvents.mixin()],
  inject: {
    groupId: {
      default: null,
    },
    upgradeToPremiumUrl: {
      default: '',
    },
    upgradeToPremiumTrackingUrl: {
      default: '',
    },
  },
  props: {
    usage: {
      type: Object,
      required: true,
    },
  },
  computed: {
    metrics() {
      const {
        seatsUsed,
        computeMinutesUsed,
        creditsUsed,
        freeSeatsLimit,
        freeComputeMinutesLimit,
      } = this.usage;

      return [
        {
          key: 'seats',
          title: s__('BillingPlans|Seats'),
          value: seatsUsed,
          qualifies: seatsUsed >= POST_TRIAL_USAGE_SEATS_THRESHOLD,
          comparison: sprintf(s__('BillingPlans|%{count} available in Free'), {
            count: formatNumber(freeSeatsLimit),
          }),
        },
        {
          key: 'compute-minutes',
          title: s__('BillingPlans|Compute minutes'),
          value: computeMinutesUsed,
          qualifies: computeMinutesUsed >= POST_TRIAL_USAGE_COMPUTE_MINUTES_THRESHOLD,
          comparison: sprintf(s__('BillingPlans|%{count} available in Free'), {
            count: formatNumber(freeComputeMinutesLimit),
          }),
        },
        {
          key: 'credits',
          title: s__('BillingPlans|Credits'),
          value: creditsUsed,
          qualifies: creditsUsed !== null && creditsUsed >= POST_TRIAL_USAGE_CREDITS_THRESHOLD,
          comparison: s__('BillingPlans|Not available in Free'),
        },
      ].filter(({ qualifies }) => qualifies);
    },
    hasMetrics() {
      return this.metrics.length > 0;
    },
    trackingProperties() {
      return {
        label: this.hasMetrics ? 'usage' : 'low_usage',
        property: this.metrics.map(({ key }) => key).join(','),
      };
    },
  },
  mounted() {
    if (this.$refs.card) {
      this.trackEvent('view_post_trial_usage_card_group_billing', this.trackingProperties);
    }
  },
  methods: {
    formatValue(value) {
      return formatNumber(value, { maximumFractionDigits: 0 });
    },
    handleCtaClick() {
      this.trackEvent(
        'click_upgrade_on_post_trial_usage_card_group_billing',
        this.trackingProperties,
      );
      axios.post(this.upgradeToPremiumTrackingUrl).catch(() => {});
    },
    handleDismiss(dismiss) {
      this.trackEvent('dismiss_post_trial_usage_card_group_billing', this.trackingProperties);
      dismiss();
    },
  },
};
</script>

<template>
  <user-group-callout-dismisser
    :feature-name="usage.calloutFeatureName"
    :group-id="groupId"
    skip-query
  >
    <template #default="{ dismiss, shouldShowCallout }">
      <div
        v-if="shouldShowCallout"
        ref="card"
        class="gl-border gl-relative gl-mt-6 gl-rounded-xl gl-bg-subtle gl-p-5"
        data-testid="post-trial-usage-card"
      >
        <div class="gl-flex gl-flex-col gl-gap-6 gl-pr-7 @md/panel:gl-flex-row">
          <div class="gl-flex gl-flex-col gl-gap-5" :class="{ '@md/panel:gl-w-2/5': hasMetrics }">
            <div class="gl-flex gl-flex-col gl-gap-3">
              <h3 class="gl-heading-3 gl-mb-0">
                {{ s__('BillingPlans|Your GitLab Ultimate trial has ended') }}
              </h3>

              <p v-if="hasMetrics" class="gl-mb-0 gl-text-subtle">
                {{
                  s__(
                    'BillingPlans|See how your trial usage compares to the Free plan, and upgrade to keep your team at full capacity.',
                  )
                }}
              </p>
              <p
                v-else
                class="gl-mb-0 gl-text-subtle"
                data-testid="post-trial-usage-card-low-usage"
              >
                {{
                  s__(
                    "BillingPlans|Upgrade to a paid plan to keep access to GitLab's paid features.",
                  )
                }}
              </p>
            </div>

            <gl-button
              class="gl-self-start"
              :href="upgradeToPremiumUrl"
              referrerpolicy="no-referrer-when-downgrade"
              data-testid="post-trial-usage-card-cta"
              @click="handleCtaClick"
              >{{ s__('BillingPlans|Upgrade to Premium') }}</gl-button
            >
          </div>

          <dl
            v-if="hasMetrics"
            class="gl-mb-0 gl-flex gl-flex-1 gl-flex-col gl-gap-5 @md/panel:gl-flex-row @md/panel:gl-gap-0"
          >
            <div
              v-for="(metric, index) in metrics"
              :key="metric.key"
              class="gl-flex gl-flex-col gl-gap-2 @md/panel:gl-w-1/3"
              :class="{ '@md/panel:gl-border-l @md/panel:gl-pl-6': index > 0 }"
              :data-testid="`post-trial-usage-metric-${metric.key}`"
            >
              <dt class="gl-font-bold">{{ metric.title }}</dt>
              <dd class="gl-heading-2 gl-mb-0">{{ formatValue(metric.value) }}</dd>
              <dd class="gl-mb-0 gl-text-sm gl-text-subtle">{{ metric.comparison }}</dd>
            </div>
          </dl>
        </div>

        <gl-button
          class="gl-absolute gl-right-3 gl-top-3"
          category="tertiary"
          icon="close"
          :aria-label="s__('BillingPlans|Dismiss trial usage summary')"
          data-testid="post-trial-usage-card-dismiss"
          @click="handleDismiss(dismiss)"
        />
      </div>
    </template>
  </user-group-callout-dismisser>
</template>
