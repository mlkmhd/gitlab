<script>
import {
  GlButton,
  GlCard,
  GlLink,
  GlSkeletonLoader,
  GlSprintf,
  GlTooltipDirective,
} from '@gitlab/ui';
import { GlSingleStat } from '@gitlab/ui/src/charts';

export default {
  name: 'StatisticsCardRow',
  components: {
    GlButton,
    GlCard,
    GlLink,
    GlSkeletonLoader,
    GlSingleStat,
    GlSprintf,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    cards: {
      type: Array,
      required: true,
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
    error: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['view-projects'],
};
</script>

<template>
  <div class="gl-mb-4 gl-grid gl-grid-cols-2 gl-gap-4 md:gl-grid-cols-4">
    <template v-if="loading">
      <gl-card v-for="n in cards.length" :key="n">
        <gl-skeleton-loader :lines="2" />
      </gl-card>
    </template>
    <template v-else>
      <gl-card
        v-for="card in cards"
        :key="card.title"
        header-class="gl-font-bold"
        body-class="gl-flex gl-flex-col"
      >
        <template #header>
          <div class="gl-flex gl-items-center gl-gap-2">
            {{ card.title }}
            <gl-button
              v-if="card.info"
              v-gl-tooltip
              :title="card.info"
              :aria-label="card.info"
              category="tertiary"
              size="small"
              icon="information-o"
            />
          </div>
        </template>
        <gl-single-stat
          v-if="error || !card.items"
          title=""
          :value="error ? __('—') : card.value"
        />
        <ul v-else class="gl-m-0 gl-list-none gl-p-0 gl-text-lg gl-font-bold">
          <li v-for="item in card.items" :key="item">{{ item }}</li>
        </ul>
        <span class="gl-mt-auto gl-text-subtle">{{ card.description }}</span>
        <hr v-if="!card.linkText || card.to || card.href" class="gl-my-3" />
        <span v-if="card.linkMessage">
          <gl-sprintf :message="card.linkMessage">
            <template #link="{ content }">
              <gl-link :href="card.href" data-testid="card-message-link">{{ content }}</gl-link>
            </template>
          </gl-sprintf>
        </span>
        <gl-link
          v-else-if="card.linkText && (card.to || card.href)"
          class="gl-self-start"
          :to="card.to"
          :href="card.href"
        >
          {{ card.linkText }}
        </gl-link>
        <gl-button
          v-else-if="!card.linkText"
          class="gl-self-start"
          variant="link"
          @click="$emit('view-projects', card)"
        >
          {{ __('View projects') }}
        </gl-button>
      </gl-card>
    </template>
  </div>
</template>
