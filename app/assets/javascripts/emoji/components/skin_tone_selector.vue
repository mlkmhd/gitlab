<script>
import { GlButton, GlTooltipDirective } from '@gitlab/ui';
import { s__ } from '~/locale';
import { SKIN_TONES, variantForTone } from '../skin_tone';

// A static name, because the emoji map that backs the grid loads asynchronously.
const SWATCH_EMOJI = 'raised_hand';

const TONE_LABELS = {
  default: s__('EmojiSkinTone|Default'),
  light: s__('EmojiSkinTone|Light'),
  medium_light: s__('EmojiSkinTone|Medium-light'),
  medium: s__('EmojiSkinTone|Medium'),
  medium_dark: s__('EmojiSkinTone|Medium-dark'),
  dark: s__('EmojiSkinTone|Dark'),
};

export default {
  name: 'SkinToneSelector',
  components: {
    GlButton,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    value: {
      type: String,
      required: true,
    },
  },
  emits: ['input', 'expand', 'collapse'],
  data() {
    return {
      isExpanded: false,
    };
  },
  computed: {
    tones() {
      return SKIN_TONES.map((tone) => ({
        tone,
        emoji: variantForTone(SWATCH_EMOJI, tone),
        label: TONE_LABELS[tone],
      }));
    },
    currentEmoji() {
      return variantForTone(SWATCH_EMOJI, this.value);
    },
  },
  methods: {
    async expand() {
      this.isExpanded = true;
      this.$emit('expand');

      await this.$nextTick();
      this.focusTone(this.value);
    },
    async collapse() {
      this.isExpanded = false;
      this.$emit('collapse');

      await this.$nextTick();
      this.$refs.toggle?.$el.focus();
    },
    select(tone) {
      if (tone !== this.value) this.$emit('input', tone);

      this.collapse();
    },
    focusTone(tone) {
      this.$refs[`tone-${tone}`]?.[0]?.$el.focus();
    },
    onKeydown(event) {
      if (event.key === 'Escape') {
        // The dropdown closes on Escape otherwise; this only collapses the row.
        event.stopPropagation();
        this.collapse();
        return;
      }

      const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key];

      if (step) {
        event.preventDefault();
        const index = SKIN_TONES.indexOf(event.target.dataset.tone ?? this.value);
        this.focusTone(SKIN_TONES[(index + step + SKIN_TONES.length) % SKIN_TONES.length]);
      }
    },
  },
  i18n: {
    chooseTone: s__('EmojiSkinTone|Choose your default skin tone'),
  },
};
</script>

<template>
  <div
    v-if="isExpanded"
    v-gl-tooltip
    :title="$options.i18n.chooseTone"
    :aria-label="$options.i18n.chooseTone"
    role="radiogroup"
    class="gl-flex gl-gap-1"
    data-testid="skin-tone-options"
    @keydown="onKeydown"
  >
    <gl-button
      v-for="{ tone, emoji, label } in tones"
      :key="tone"
      :ref="`tone-${tone}`"
      role="radio"
      category="tertiary"
      class="!gl-h-7 !gl-w-7 !gl-rounded-full !gl-p-0 gl-text-lg"
      button-text-classes="!gl-hidden"
      :selected="tone === value"
      :aria-checked="tone === value ? 'true' : 'false'"
      :aria-label="label"
      :tabindex="tone === value ? 0 : -1"
      :data-tone="tone"
      data-testid="skin-tone-option"
      @click="select(tone)"
    >
      <template #emoji>
        <gl-emoji :data-name="emoji" class="!gl-mr-0" />
      </template>
    </gl-button>
  </div>
  <gl-button
    v-else
    ref="toggle"
    v-gl-tooltip
    :title="$options.i18n.chooseTone"
    :aria-label="$options.i18n.chooseTone"
    aria-haspopup="true"
    aria-expanded="false"
    category="tertiary"
    class="!gl-h-7 !gl-w-7 !gl-rounded-full !gl-p-0 gl-text-lg"
    button-text-classes="!gl-hidden"
    data-testid="skin-tone-toggle"
    @click="expand"
  >
    <template #emoji>
      <gl-emoji :data-name="currentEmoji" class="!gl-mr-0" />
    </template>
  </gl-button>
</template>
