<script>
import { GlButton, GlIcon, GlLink, GlTooltipDirective } from '@gitlab/ui';
import { sprintf, __, s__ } from '~/locale';
import { TIERS, ITEM_VARIANTS } from './constants';

export default {
  name: 'FeatureLibraryItem',
  components: { GlButton, GlIcon, GlLink },
  directives: { GlTooltip: GlTooltipDirective },
  i18n: {
    pinLabel: s__('FeatureLibrary|Pin %{title}'),
    pinTooltip: s__('FeatureLibrary|Pin'),
    unpinTooltip: s__('FeatureLibrary|Unpin'),
    learnMoreLabel: s__('FeatureLibrary|Learn more about %{title}'),
  },
  props: {
    supportsPins: {
      type: Boolean,
      required: false,
      default: false,
    },
    item: {
      type: Object,
      required: true,
    },
    pinned: {
      type: Boolean,
      required: false,
      default: false,
    },
    solidBackground: {
      type: Boolean,
      required: false,
      default: false,
    },
    variant: {
      type: String,
      required: false,
      default: ITEM_VARIANTS.DEFAULT,
      validator: (value) => Object.values(ITEM_VARIANTS).includes(value),
    },
  },
  emits: ['pin-toggle', 'navigate'],
  computed: {
    isLocked() {
      return this.variant === ITEM_VARIANTS.LOCKED;
    },
    showPin() {
      return !this.isLocked && this.supportsPins;
    },
    showLearnMore() {
      return this.isLocked && Boolean(this.item.docs_url);
    },
    cardClasses() {
      // A locked card isn't a link, so it has no hover state.
      if (this.isLocked) return 'gl-bg-section';

      return this.solidBackground
        ? 'gl-bg-default hover:gl-shadow-md'
        : 'gl-bg-section hover:gl-bg-subtle';
    },
    // A locked item shows the label the catalog endpoint sends, such as "New with Premium".
    footerLabel() {
      return this.isLocked ? this.item.label?.text || '' : this.tierLabel;
    },
    learnMoreAriaLabel() {
      return sprintf(this.$options.i18n.learnMoreLabel, { title: this.item.title });
    },
    tierLabel() {
      switch (this.item.tier) {
        case TIERS.PREMIUM:
          return __('Premium');
        case TIERS.ULTIMATE:
          return __('Ultimate');
        case TIERS.ADD_ON:
          return __('Add-on');
        default:
          return __('Free');
      }
    },
    pinAriaLabel() {
      return sprintf(this.$options.i18n.pinLabel, { title: this.item.title });
    },
    pinIconName() {
      return this.pinned ? 'thumbtack-solid' : 'thumbtack';
    },
    pinTooltipText() {
      return this.pinned ? this.$options.i18n.unpinTooltip : this.$options.i18n.pinTooltip;
    },
  },
  methods: {
    onPinClick() {
      this.$emit('pin-toggle', this.item.id, !this.pinned, this.item.title);
    },
    onNavigate() {
      this.$emit('navigate', this.item.id);
    },
    // eslint-disable-next-line vue/no-unused-properties -- invoked externally via this.$refs.searchResultItems in feature_library_modal.vue
    focus() {
      this.$refs.titleLink?.$el?.focus();
    },
  },
};
</script>

<template>
  <li
    class="gl-flex gl-flex-col gl-rounded-xl gl-border-1 gl-border-solid gl-border-section gl-pt-4"
    :class="cardClasses"
  >
    <!-- The title link stretches over this wrapper only, so the pin action
         stays outside the link's click target. -->
    <div class="gl-relative gl-grow gl-px-4" data-testid="feature-library-item-content">
      <span class="gl-inline-flex gl-items-center gl-gap-2">
        <gl-icon :name="item.icon" class="gl-shrink-0" />
        <gl-link
          v-if="!isLocked"
          ref="titleLink"
          variant="meta"
          :href="item.link"
          class="gl-text-lg gl-font-semibold gl-stretched-link"
          data-testid="feature-library-item-title"
          @click="onNavigate"
        >
          {{ item.title }}
        </gl-link>
        <span
          v-else
          class="gl-text-lg gl-font-semibold gl-text-strong"
          data-testid="feature-library-item-title"
        >
          {{ item.title }}
        </span>
      </span>

      <p data-testid="feature-library-item-description" class="gl-mb-0 gl-mt-1 gl-text-subtle">
        {{ item.description }}
      </p>
    </div>
    <div
      class="gl-mt-3 gl-flex gl-items-center gl-justify-between gl-border-t-1 gl-border-t-section gl-py-3 gl-pl-4 gl-pr-3 gl-border-t-solid"
    >
      <span data-testid="feature-library-item-footer-label" class="gl-text-sm gl-text-subtle">
        {{ footerLabel }}
      </span>
      <gl-button
        v-if="showPin"
        v-gl-tooltip.hover="pinTooltipText"
        category="tertiary"
        size="small"
        :icon="pinIconName"
        :aria-label="pinAriaLabel"
        :aria-pressed="String(pinned)"
        :selected="pinned"
        @click="onPinClick"
      />
      <gl-link
        v-else-if="showLearnMore"
        :href="item.docs_url"
        target="_blank"
        class="gl-text-sm gl-font-semibold"
        :aria-label="learnMoreAriaLabel"
        data-testid="feature-library-item-learn-more"
      >
        {{ __('Learn more') }}
      </gl-link>
    </div>
  </li>
</template>
