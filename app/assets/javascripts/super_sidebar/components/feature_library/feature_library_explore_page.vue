<script>
import { GlButton } from '@gitlab/ui';
import { s__ } from '~/locale';
import { getScrollBehavior } from '~/lib/utils/scroll_utils';
import ScrollScrim from '~/vue_shared/components/scroll_scrim/scroll_scrim.vue';
import { ITEM_VARIANTS } from './constants';
import FeatureLibraryItem from './feature_library_item.vue';

const ALL_SECTIONS = 'all';
// Leaves room above a heading for its 3px focus ring.
const HEADING_SCROLL_MARGIN = 4;
// A clicked chip stays locked until its scroll ends or the user takes over. Fallbacks to
// `scrollend` are needed until it's widely available.
const CHIP_UNLOCK_EVENTS = ['scrollend', 'wheel', 'touchstart', 'keydown', 'pointerdown'];

export default {
  name: 'FeatureLibraryExplorePage',
  components: { GlButton, ScrollScrim, FeatureLibraryItem },
  props: {
    page: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      selectedChipId: ALL_SECTIONS,
      isChipLockedOnScroll: false,
    };
  },
  computed: {
    sections() {
      const {
        highlights,
        credits,
        highlights_title: highlightsTitle,
        credits_title: creditsTitle,
      } = this.page;

      return [
        { key: 'highlights', title: highlightsTitle, items: highlights },
        { key: 'credits', title: creditsTitle, items: credits },
        ...this.categorySections,
      ].filter((section) => section.items.length > 0);
    },
    categorySections() {
      return this.page.categories
        .filter(({ items }) => items.length > 0)
        .map(({ id, title, items }) => ({ key: `category-${id}`, title, items }));
    },
    // The highlights and credits sections open the page, so "All" covers them.
    sectionChips() {
      return [
        {
          id: ALL_SECTIONS,
          title: s__('FeatureLibrary|All'),
          ariaLabel: s__('FeatureLibrary|All sections'),
        },
        ...this.categorySections.map(({ key, title }) => ({ id: key, title })),
      ];
    },
  },
  mounted() {
    const scrollArea = this.scrollAreaElement();

    scrollArea.addEventListener('scroll', this.onScroll, { passive: true });
    CHIP_UNLOCK_EVENTS.forEach((event) =>
      scrollArea.addEventListener(event, this.unlockChip, { passive: true }),
    );
  },
  beforeDestroy() {
    const scrollArea = this.scrollAreaElement();

    scrollArea.removeEventListener('scroll', this.onScroll);
    CHIP_UNLOCK_EVENTS.forEach((event) => scrollArea.removeEventListener(event, this.unlockChip));
  },
  methods: {
    scrollAreaElement() {
      return this.$refs.scrollArea.$el;
    },
    // Match by key rather than position: Vue 2's v-for ref arrays don't track render order.
    findHeading(sectionKey) {
      return (this.$refs.headings || []).find(
        (heading) => heading.dataset.sectionKey === sectionKey,
      );
    },
    // Measured from inside the top border that ScrollScrim adds once scrolled.
    headingOffset(heading, scrollArea) {
      const areaTop = scrollArea.getBoundingClientRect().top + scrollArea.clientTop;
      return heading.getBoundingClientRect().top - areaTop;
    },
    isChipSelected(chipId) {
      return this.selectedChipId === chipId;
    },
    selectChip(chipId) {
      const scrollArea = this.scrollAreaElement();
      const isAll = chipId === ALL_SECTIONS;
      const heading = this.findHeading(isAll ? this.sections[0].key : chipId);

      this.selectedChipId = chipId;
      this.isChipLockedOnScroll = true;

      const top = isAll
        ? 0
        : scrollArea.scrollTop + this.headingOffset(heading, scrollArea) - HEADING_SCROLL_MARGIN;
      scrollArea.scrollTo({ top, behavior: getScrollBehavior() });
      heading.focus({ preventScroll: true });
    },
    unlockChip() {
      this.isChipLockedOnScroll = false;
    },
    onScroll() {
      if (this.isChipLockedOnScroll) return;

      this.selectedChipId = this.computeSelectedChipId();
    },
    // The last category whose heading has reached the top. At the bottom, the last category,
    // so a short last section can still be selected.
    computeSelectedChipId() {
      const scrollArea = this.scrollAreaElement();
      const { scrollTop, clientHeight, scrollHeight } = scrollArea;
      const lastCategory = this.categorySections.at(-1);

      if (scrollTop <= 0 || !lastCategory) return ALL_SECTIONS;
      if (scrollTop + clientHeight >= scrollHeight - 1) return lastCategory.key;

      const reached = this.categorySections.findLast((section) => {
        const heading = this.findHeading(section.key);
        // 1px of slack for subpixel rounding.
        return heading && this.headingOffset(heading, scrollArea) <= HEADING_SCROLL_MARGIN + 1;
      });

      return reached?.key || ALL_SECTIONS;
    },
  },
  lockedVariant: ITEM_VARIANTS.LOCKED,
};
</script>

<template>
  <div class="gl-flex gl-min-h-0 gl-grow gl-flex-col" data-testid="feature-library-explore-page">
    <div
      v-if="categorySections.length > 0"
      role="group"
      :aria-label="s__('FeatureLibrary|Jump to section')"
      data-testid="feature-library-explore-chips"
      class="-gl-ml-2 gl-mb-4 gl-flex gl-shrink-0 gl-gap-2 gl-overflow-x-auto gl-p-2"
    >
      <gl-button
        v-for="chip in sectionChips"
        :key="chip.id"
        category="secondary"
        size="small"
        class="gl-shrink-0"
        :selected="isChipSelected(chip.id)"
        :aria-label="chip.ariaLabel"
        :aria-current="isChipSelected(chip.id) ? 'location' : null"
        data-testid="feature-library-explore-chip"
        @click="selectChip(chip.id)"
      >
        {{ chip.title }}
      </gl-button>
    </div>
    <scroll-scrim
      ref="scrollArea"
      data-testid="feature-library-explore-scroll-area"
      class="feature-library-scroll-area feature-library-scroll-bleed gl-min-h-0 gl-grow"
    >
      <div class="feature-library-scroll-inset">
        <section
          v-for="section in sections"
          :key="section.key"
          data-testid="feature-library-explore-section"
          class="gl-mb-3"
        >
          <h3
            ref="headings"
            :data-section-key="section.key"
            tabindex="-1"
            class="gl-m-0 gl-p-3 gl-text-base gl-font-semibold gl-text-subtle"
          >
            {{ section.title }}
          </h3>
          <ul
            class="gl-grid gl-list-none gl-grid-cols-1 gl-gap-3 gl-p-0 sm:gl-grid-cols-2 md:gl-grid-cols-3"
          >
            <feature-library-item
              v-for="item in section.items"
              :key="item.id"
              :item="item"
              :variant="$options.lockedVariant"
            />
          </ul>
        </section>
      </div>
    </scroll-scrim>
  </div>
</template>
