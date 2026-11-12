<script>
import { GlButton } from '@gitlab/ui';
import { marked } from 'marked';
import HandRaiseLeadButton from 'ee/hand_raise_leads/hand_raise_lead/components/hand_raise_lead_button.vue';
import { sanitize } from '~/lib/dompurify';
import { strictMarkdownConfig } from '~/lib/utils/text_utility';
import { mergeUrlParams } from '~/lib/utils/url_utility';
import SafeHtml from '~/vue_shared/directives/safe_html';
import { EventsTracker } from 'ee/ai/duo_agentic_chat/observability/events_tracker';
import { s__ } from '~/locale';

const DEFAULT_PLAN_NAME = 'ultimate';
const TRACKING_EVENT_UPGRADE = 'click_upgrade_subscription_duo_chat_tier_access_denied';
const TRACKING_EVENT_LEARN_MORE = 'click_learn_more_duo_chat_tier_access_denied';
const UNKNOWN_PLAN_LABEL = 'unknown_plan';
const PLAN_LABELS = {
  premium: 'premium_plan',
  ultimate: 'ultimate_plan',
};
const HAND_RAISE_GLM_CONTENT = 'gitlab-duo-chat-tier-access-denied';
const HAND_RAISE_BUTTON_ATTRIBUTES = {
  variant: 'default',
  category: 'primary',
  'data-testid': 'tier-access-denied-talk-to-sales-button',
  // No named event fires for this click, so the click catch-all reports it
  // under this stable id.
  'data-track-id': 'tier-access-denied-talk-to-sales',
};

export default {
  name: 'MessageTierAccessDenied',
  i18n: {
    upgrade: s__('DuoAgenticChat|Upgrade subscription'),
    talkToSales: s__('DuoAgenticChat|Talk to sales'),
  },
  components: {
    GlButton,
    HandRaiseLeadButton,
  },
  directives: {
    SafeHtml,
  },
  props: {
    message: {
      required: true,
      type: Object,
    },
    canBuyAddon: {
      type: Boolean,
      required: false,
      default: false,
    },
    tierUpgradePath: {
      type: String,
      required: false,
      default: '',
    },
    isHandRaiseLeadAvailable: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    parsedContent() {
      const { content } = this.message;
      if (!content) return '';
      // When a CTA shows, collapse paragraph breaks so a trailing link
      // (e.g. "Learn more") renders inline with the message instead of below it.
      const source =
        this.canBuyAddon || this.isHandRaiseLeadAvailable
          ? content.replace(/\n+/g, ' ').trim()
          : content;
      return sanitize(marked.parse(source), strictMarkdownConfig);
    },
    rawRequiredPlan() {
      return this.message.required_plan ?? null;
    },
    purchasePlanName() {
      return this.rawRequiredPlan ?? DEFAULT_PLAN_NAME;
    },
    upgradeTrackingLabel() {
      return PLAN_LABELS[this.rawRequiredPlan] ?? UNKNOWN_PLAN_LABEL;
    },
    purchasePath() {
      return mergeUrlParams({ plan_name: this.purchasePlanName }, this.tierUpgradePath);
    },
  },
  methods: {
    onUpgradeClick() {
      EventsTracker.track(TRACKING_EVENT_UPGRADE, { label: this.upgradeTrackingLabel });
    },
    onContentClick(event) {
      if (event.target.closest('a')) {
        EventsTracker.track(TRACKING_EVENT_LEARN_MORE);
      }
    },
  },
  handRaiseGlmContent: HAND_RAISE_GLM_CONTENT,
  handRaiseButtonAttributes: HAND_RAISE_BUTTON_ATTRIBUTES,
};
</script>

<template>
  <div data-testid="tier-access-denied-message">
    <div v-if="parsedContent" v-safe-html="parsedContent" @click="onContentClick"></div>
    <hand-raise-lead-button
      v-if="isHandRaiseLeadAvailable"
      :button-text="$options.i18n.talkToSales"
      :button-attributes="$options.handRaiseButtonAttributes"
      :glm-content="$options.handRaiseGlmContent"
    />
    <gl-button v-else-if="canBuyAddon" :href="purchasePath" target="_blank" @click="onUpgradeClick">
      {{ $options.i18n.upgrade }}
    </gl-button>
  </div>
</template>
