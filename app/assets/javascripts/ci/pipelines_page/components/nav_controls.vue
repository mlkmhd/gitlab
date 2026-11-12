<script>
import { GlButton, GlDisclosureDropdown, GlTooltipDirective } from '@gitlab/ui';
import { __, s__ } from '~/locale';

export default {
  name: 'PipelineNavControls',
  components: {
    GlButton,
    GlDisclosureDropdown,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  i18n: {
    moreActions: __('More actions'),
    viewAnalytics: s__('Pipelines|View analytics'),
  },
  inject: ['pipelinesAnalyticsPath'],
  props: {
    isResetCacheButtonLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
    newPipelinePath: {
      type: String,
      required: false,
      default: null,
    },
    resetCachePath: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['reset-runners-cache'],
  data() {
    return {
      isDropdownVisible: false,
    };
  },
  computed: {
    moreActionsItems() {
      if (!this.resetCachePath) return [];

      return [
        {
          text: s__('Pipelines|Clear runner caches'),
          action: this.onClickResetCache,
          extraAttrs: { 'data-testid': 'clear-cache-button' },
        },
      ];
    },
    moreActionsTooltip() {
      return !this.isDropdownVisible ? this.$options.i18n.moreActions : '';
    },
  },
  methods: {
    onClickResetCache() {
      this.$emit('reset-runners-cache', this.resetCachePath);
    },
  },
};
</script>
<template>
  <div class="gl-flex gl-items-center gl-gap-3">
    <gl-button
      v-if="newPipelinePath"
      :href="newPipelinePath"
      variant="confirm"
      category="primary"
      size="small"
      class="js-run-pipeline"
      data-testid="run-pipeline-button"
    >
      {{ s__('Pipeline|New pipeline') }}
    </gl-button>

    <gl-button
      v-if="pipelinesAnalyticsPath"
      v-gl-tooltip.bottom
      :href="pipelinesAnalyticsPath"
      :title="$options.i18n.viewAnalytics"
      :aria-label="$options.i18n.viewAnalytics"
      icon="cicd-analytics"
      category="tertiary"
      size="small"
      data-testid="view-analytics-link"
    />

    <gl-disclosure-dropdown
      v-if="moreActionsItems.length"
      v-gl-tooltip.bottom="moreActionsTooltip"
      :items="moreActionsItems"
      :toggle-text="$options.i18n.moreActions"
      :loading="isResetCacheButtonLoading"
      icon="ellipsis_h"
      category="tertiary"
      size="small"
      placement="bottom-end"
      text-sr-only
      no-caret
      data-testid="pipelines-more-actions-dropdown"
      @shown="isDropdownVisible = true"
      @hidden="isDropdownVisible = false"
    />
  </div>
</template>
