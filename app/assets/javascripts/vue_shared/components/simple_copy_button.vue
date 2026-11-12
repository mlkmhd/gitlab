<script>
import { GlButton, GlTooltipDirective } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { hideGlTooltip } from '~/vue_shared/utils/tooltips';
import { __ } from '~/locale';
import { copyToClipboard } from '~/lib/utils/copy_to_clipboard';
import { I18N_ERROR_MESSAGE, FEEDBACK_DURATION_MS } from '~/behaviors/copy_to_clipboard';
import * as Sentry from '~/sentry/sentry_browser_wrapper';

/**
 * Button that programmatically copies text to the clipboard upon click. Attempts
 * to copy in both secure and non-secure contexts.
 *
 * It is meant to supersede `<clipboard-button>`, should work
 * in modals and it does not have a ClipboardJS dependency.
 *
 * After copying, the icon briefly changes to a check (or an error icon when copying
 * failed), and the result is announced to screen readers with `ariaNotify`.
 *
 * @example
 *
 * <simple-copy-button
 *   title="Copy URL"
 *   text="http://example.com"
 * />
 *
 * Other customization options:
 *
 * <simple-copy-button
 *   title="Copy another URL"
 *   text="http://another.example.com"
 *   class="custom-class-1 custom-class-2"
 *   variant="confirm"
 *   @copied="onCopied"
 *   @error="onError" # Rare, but can happen
 * />
 *
 * See: https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts
 */

export default {
  name: 'SimpleCopyButton',
  i18n: {
    copied: __('Copied to clipboard.'),
    error: I18N_ERROR_MESSAGE,
  },
  FEEDBACK_DURATION_MS,
  components: {
    GlButton,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    id: {
      type: String,
      required: false,
      default: () => uniqueId('clipboard-button-'),
    },
    text: {
      type: String,
      required: true,
    },
    title: {
      type: String,
      required: false,
      default: __('Copy'),
    },
    tooltipPlacement: {
      type: String,
      required: false,
      default: 'top',
    },
    tooltipContainer: {
      type: String,
      required: false,
      default: null,
    },
    category: {
      type: String,
      required: false,
      default: 'secondary',
    },
    size: {
      type: String,
      required: false,
      default: 'medium',
    },
    variant: {
      type: String,
      required: false,
      default: 'default',
    },
    icon: {
      type: String,
      required: false,
      default: 'copy-to-clipboard',
    },
  },
  emits: ['copied', 'error'],
  data() {
    return {
      feedbackIcon: null,
      feedbackTimeout: null,
    };
  },
  computed: {
    currentIcon() {
      return this.feedbackIcon || this.icon;
    },
  },
  beforeDestroy() {
    clearTimeout(this.feedbackTimeout);
  },
  methods: {
    async onClick() {
      try {
        await copyToClipboard(this.text, this.$el);

        this.showFeedback('check', this.$options.i18n.copied);
        this.$emit('copied');
      } catch (e) {
        this.showFeedback('error', this.$options.i18n.error);
        this.$emit('error', e);
        Sentry.captureException(e);
      }
    },
    showFeedback(icon, message) {
      this.feedbackIcon = icon;
      this.$el.ariaNotify(message);

      clearTimeout(this.feedbackTimeout);
      this.feedbackTimeout = setTimeout(() => {
        this.feedbackIcon = null;
      }, FEEDBACK_DURATION_MS);
    },
    onMouseleave() {
      // Tooltip still appears after clicking focusing on the button, ensure it's hidden
      hideGlTooltip(this, this.id);
    },
  },
};
</script>
<template>
  <gl-button
    :id="id"
    v-gl-tooltip="{
      title,
      placement: tooltipPlacement,
      container: tooltipContainer,
    }"
    :aria-label="$attrs.ariaLabel || title"
    :category="category"
    :size="size"
    :icon="currentIcon"
    :variant="variant"
    @click="onClick"
    @mouseleave="onMouseleave"
  />
</template>
