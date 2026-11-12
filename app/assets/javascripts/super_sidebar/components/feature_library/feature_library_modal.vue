<script>
import {
  GlModal,
  GlSearchBoxByType,
  GlButton,
  GlIcon,
  GlCollapse,
  GlEmptyState,
  GlLoadingIcon,
} from '@gitlab/ui';
import FeatureLibraryUpgradeCta from 'ee_component/super_sidebar/components/feature_library/feature_library_upgrade_cta.vue';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__, n__, sprintf } from '~/locale';
import axios from '~/lib/utils/axios_utils';
import { DEFAULT_DEBOUNCE_AND_THROTTLE_MS } from '~/lib/utils/constants';
import { HTTP_STATUS_TOO_MANY_REQUESTS } from '~/lib/utils/http_status';
import {
  onboardingFeatureLibrarySearchPath,
  onboardingFeatureLibraryAiSearchPath,
  onboardingFeatureLibraryCatalogPath,
} from '~/lib/utils/path_helpers/feature_library';
import { InternalEvents } from '~/tracking';
import ScrollScrim from '~/vue_shared/components/scroll_scrim/scroll_scrim.vue';
import {
  EVENT_OPEN_FEATURE_LIBRARY_MODAL,
  EVENT_SEARCH_FEATURES_IN_FEATURE_LIBRARY_MODAL,
  EVENT_CLICK_CATEGORY_FILTER_IN_FEATURE_LIBRARY_MODAL,
  EVENT_PIN_ITEM_IN_FEATURE_LIBRARY_MODAL,
  EVENT_UNPIN_ITEM_IN_FEATURE_LIBRARY_MODAL,
  EVENT_NAVIGATE_TO_FEATURE_FROM_FEATURE_LIBRARY_MODAL,
  EVENT_SEARCH_WITH_GEMINI_IN_FEATURE_LIBRARY_MODAL,
} from '../../tracking_constants';
import { PANEL_TYPES } from '../../constants';
import { isNavItemHidden } from '../../utils';
import { MODAL_ID, ITEMS_PER_RENDER_FRAME, SENTRY_CONTEXT, LABEL_TYPE_NEW } from './constants';
import { rankSearchResults } from './search';
import FeatureLibraryItem from './feature_library_item.vue';
import FeatureLibraryExplorePageButton from './feature_library_explore_page_button.vue';
import FeatureLibraryExplorePage from './feature_library_explore_page.vue';

const SETTINGS_MENU_ID = 'settings_menu';
const trackingMixin = InternalEvents.mixin();
const MIN_SEARCH_QUERY_LENGTH = 2;
const ALL_CATEGORIES = 'all';

// The pages aren't known until the catalog loads, so the skeletons assume Premium and Ultimate.
const LOADING_PAGE_BUTTON_COUNT = 2;

export default {
  name: 'FeatureLibraryModal',
  components: {
    GlModal,
    GlSearchBoxByType,
    GlButton,
    GlIcon,
    GlCollapse,
    GlEmptyState,
    GlLoadingIcon,
    ScrollScrim,
    FeatureLibraryItem,
    FeatureLibraryExplorePageButton,
    FeatureLibraryExplorePage,
    FeatureLibraryUpgradeCta,
  },
  mixins: [trackingMixin],
  modalId: MODAL_ID,
  DEFAULT_DEBOUNCE_AND_THROTTLE_MS,
  searchInputDescriptionId: 'feature-library-search-input-description',
  i18n: {
    geminiSearching: s__('FeatureLibrary|Searching with Gemini …'),
    searchInProgress: s__('FeatureLibrary|Searching for features …'),
    geminiEmptyState: s__(
      "FeatureLibrary|Gemini couldn't find a matching feature. Try different keywords.",
    ),
    searchInputDescription: s__(
      'FeatureLibrary|Press Enter or the down arrow key to move to the first search result.',
    ),
  },
  inject: {
    panelType: { default: '' },
    resourceId: { default: null },
    aiSearchAvailable: { default: false },
    explorePagesAvailable: { default: false },
  },
  props: {
    supportsPins: {
      type: Boolean,
      required: false,
      default: false,
    },
    sections: {
      type: Array,
      required: false,
      default: () => [],
    },
    currentPinnedIds: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  emits: ['pin-toggle'],
  data() {
    return {
      searchQuery: '',
      selectedCategory: ALL_CATEGORIES,
      collapsedSectionIds: [],
      searchResultIds: [],
      isSearching: false,
      latestQuery: null,
      renderLimit: ITEMS_PER_RENDER_FRAME,
      revealFrameId: null,
      geminiResultIds: [],
      isGeminiSearching: false,
      geminiSearched: false,
      geminiHidden: false,
      geminiErrorMessage: null,
      exploreCatalog: null,
      isLoadingExploreCatalog: false,
      exploreCatalogRequested: false,
      isModalOpen: false,
      activeExplorePlan: null,
    };
  },
  computed: {
    trimmedQuery() {
      return this.searchQuery.trim();
    },
    hasSearchableQuery() {
      return this.trimmedQuery.length >= MIN_SEARCH_QUERY_LENGTH;
    },
    searchPlaceholder() {
      switch (this.panelType) {
        case PANEL_TYPES.PROJECT:
          return s__('FeatureLibrary|Search features in this project');
        case PANEL_TYPES.GROUP:
          return s__('FeatureLibrary|Search features in this group');
        default:
          return s__('FeatureLibrary|Search GitLab features');
      }
    },
    catalogSections() {
      return this.sections
        .map((section) => ({
          ...section,
          items: (section.items || []).filter((item) => !isNavItemHidden(item)),
        }))
        .filter((section) => {
          // The settings menu currently remains in the super sidebar and should not appear within
          // the modal, nor have its items pinnable.
          if (section.id === SETTINGS_MENU_ID) {
            return false;
          }
          return section.items.length > 0;
        });
    },
    catalog() {
      return this.catalogSections.flatMap((section) =>
        section.items.map((item) => ({
          id: item.id,
          title: item.title,
          description: item.description,
          icon: item.library_icon || item.icon,
          tier: item.tier,
          category: section.id,
          link: item.link,
        })),
      );
    },
    catalogById() {
      return Object.fromEntries(this.catalog.map((item) => [item.id, item]));
    },
    categoryOptions() {
      return [
        { id: ALL_CATEGORIES, title: s__('FeatureLibrary|All') },
        ...this.catalogSections.map((section) => ({ id: section.id, title: section.title })),
      ];
    },
    scopedCatalog() {
      if (this.selectedCategory === ALL_CATEGORIES) return this.catalog;

      return this.catalog.filter((item) => item.category === this.selectedCategory);
    },
    filteredItems() {
      if (!this.trimmedQuery) return this.scopedCatalog;

      return rankSearchResults({
        catalog: this.scopedCatalog,
        query: this.trimmedQuery,
        synonymIds: this.searchResultIds,
      });
    },
    // Sections with their items, honoring the progressive reveal limit.
    // Used when not searching, so each category renders under its own heading.
    //
    // Every section heading is always included so the section list is stable
    // regardless of the reveal budget; only the items within each section are
    // limited, and the budget is distributed across sections in order.
    groupedSections() {
      let remaining = this.renderLimit;

      return this.catalogSections.map((section) => {
        const items = section.items
          .slice(0, Math.max(remaining, 0))
          .map((item) => this.catalogById[item.id])
          .filter(Boolean);

        remaining -= items.length;

        return { id: section.id, title: section.title, items };
      });
    },
    hasActiveCategoryFilter() {
      return this.selectedCategory !== ALL_CATEGORIES;
    },
    selectedCategoryLabel() {
      return this.categoryOptions.find((option) => option.id === this.selectedCategory)?.title;
    },
    categoryStatusMessage() {
      if (this.activeExplorePage || this.isSearching || !this.hasActiveCategoryFilter) return '';

      const count = this.filteredItems.length;
      return sprintf(
        n__(
          'FeatureLibrary|Showing %{count} feature in %{category}',
          'FeatureLibrary|Showing %{count} features in %{category}',
          count,
        ),
        { count, category: this.selectedCategoryLabel },
      );
    },
    showResultsGrid() {
      return Boolean(this.trimmedQuery) || this.hasActiveCategoryFilter;
    },
    showGroupedSections() {
      return !this.showResultsGrid;
    },
    showEmptyState() {
      return (
        !this.isSearching &&
        !this.isGeminiSearching &&
        (this.hasSearchableQuery || this.hasActiveCategoryFilter) &&
        this.filteredItems.length === 0 &&
        !this.showGeminiEmptyState
      );
    },
    geminiItems() {
      if (!this.geminiResultIds.length) return [];

      const shownIds = new Set(this.filteredItems.map((item) => item.id));
      const inScope = (item) =>
        this.selectedCategory === ALL_CATEGORIES || item.category === this.selectedCategory;

      return this.geminiResultIds
        .map((id) => this.catalogById[id])
        .filter((item) => item && inScope(item) && !shownIds.has(item.id));
    },
    showGeminiSection() {
      return (
        (this.isGeminiSearching || this.geminiSearched || Boolean(this.geminiErrorMessage)) &&
        !this.geminiHidden
      );
    },
    showGeminiHeader() {
      return (this.geminiSearched || Boolean(this.geminiErrorMessage)) && !this.geminiHidden;
    },
    showGeminiEmptyState() {
      return (
        this.showGeminiSection &&
        !this.isGeminiSearching &&
        !this.geminiErrorMessage &&
        this.geminiItems.length === 0
      );
    },
    showGeminiButton() {
      return (
        this.aiSearchAvailable &&
        this.resourceId &&
        this.hasSearchableQuery &&
        (!this.geminiSearched || this.geminiHidden) &&
        !this.isGeminiSearching
      );
    },
    showFooter() {
      return this.showGeminiButton && !this.activeExplorePage;
    },
    // Every page has highlights, which the sidebar never shows, so no page ends up empty.
    explorePages() {
      const pages = this.exploreCatalog?.pages || [];

      return pages.map((page) => this.withoutItemsInSidebar(page));
    },
    hasExplorePages() {
      return this.explorePages.length > 0;
    },
    showExploreEntries() {
      return this.isLoadingExploreCatalog || this.hasExplorePages;
    },
    explorePageButtons() {
      if (this.isLoadingExploreCatalog) {
        return Array.from({ length: LOADING_PAGE_BUTTON_COUNT }, (_, index) => ({
          key: `loading-${index}`,
          loading: true,
        }));
      }

      return this.explorePages.map(({ plan, title, subtitle }) => ({
        key: plan,
        plan,
        title,
        subtitle,
      }));
    },
    currentPlanContext() {
      return this.exploreCatalog?.current_plan_context || {};
    },
    activeExplorePage() {
      return this.explorePages.find(({ plan }) => plan === this.activeExplorePlan) || null;
    },
    headerTitle() {
      return this.activeExplorePage?.title || s__('FeatureLibrary|Feature catalog');
    },
    // On the first open the page buttons replace the skeletons once the catalog loads.
    showsExplorePageButtons() {
      return this.isModalOpen && this.hasExplorePages;
    },
    emptyStateTitle() {
      return s__('FeatureLibrary|No features match your search');
    },
    // An open Explore page hides the results, so their status isn't announced.
    searchStatusMessage() {
      if (this.activeExplorePage || !this.trimmedQuery) {
        return '';
      }

      if (this.filteredItems.length > 0) {
        return n__(
          'FeatureLibrary|%d feature found.',
          'FeatureLibrary|%d features found.',
          this.filteredItems.length,
        );
      }

      if (this.isSearching) {
        return this.$options.i18n.searchInProgress;
      }

      return this.emptyStateTitle;
    },
    showGeminiTopBorder() {
      // showEmptyState already requires !showGeminiEmptyState, so the two are
      // mutually exclusive: no need to check showEmptyState separately here.
      return !this.isGeminiSearching && !this.showGeminiEmptyState;
    },
    geminiStatusMessage() {
      if (!this.showGeminiSection) {
        return '';
      }

      if (this.isGeminiSearching) {
        return this.$options.i18n.geminiSearching;
      }

      if (this.geminiErrorMessage) {
        return this.geminiErrorMessage;
      }

      if (this.showGeminiEmptyState) {
        return this.$options.i18n.geminiEmptyState;
      }

      if (this.geminiItems.length > 0) {
        return n__(
          'FeatureLibrary|Gemini found %d matching feature.',
          'FeatureLibrary|Gemini found %d matching features.',
          this.geminiItems.length,
        );
      }

      return '';
    },
  },
  watch: {
    showsExplorePageButtons(shown) {
      if (shown) this.trackExplorePageButtonsViewed();
    },
  },
  beforeDestroy() {
    this.cancelReveal();
  },
  methods: {
    isPinned(itemId) {
      return this.currentPinnedIds.includes(itemId);
    },
    isSectionExpanded(sectionId) {
      return !this.collapsedSectionIds.includes(sectionId);
    },
    toggleSection(sectionId) {
      if (this.isSectionExpanded(sectionId)) {
        this.collapsedSectionIds.push(sectionId);
      } else {
        this.collapsedSectionIds = this.collapsedSectionIds.filter((id) => id !== sectionId);
      }
    },
    isCategorySelected(categoryId) {
      return this.selectedCategory === categoryId;
    },
    selectCategory(categoryId) {
      const next = this.isCategorySelected(categoryId) ? ALL_CATEGORIES : categoryId;
      this.selectedCategory = next;
      this.trackEvent(EVENT_CLICK_CATEGORY_FILTER_IN_FEATURE_LIBRARY_MODAL, { label: next });
      this.$refs.searchBox?.focusInput?.();
    },
    onShow() {
      if (!this.explorePagesAvailable || !this.resourceId || this.exploreCatalogRequested) return;

      this.loadExploreCatalog();
    },
    onShown() {
      this.$refs.searchBox?.focusInput();
      this.revealRemainingItems();
      this.trackEvent(EVENT_OPEN_FEATURE_LIBRARY_MODAL);
      this.isModalOpen = true;
    },
    async loadExploreCatalog() {
      this.exploreCatalogRequested = true;
      this.isLoadingExploreCatalog = true;

      try {
        const { data } = await axios.get(onboardingFeatureLibraryCatalogPath(), {
          params: { panel: this.panelType, resource_id: this.resourceId },
        });
        this.exploreCatalog = data;
      } catch (e) {
        // A 429 waits for the next page load, while other failures are retried on the next open.
        if (e.response?.status !== HTTP_STATUS_TOO_MANY_REQUESTS) {
          this.exploreCatalogRequested = false;
          Sentry.captureException(e, SENTRY_CONTEXT);
        }
      } finally {
        this.isLoadingExploreCatalog = false;
      }
    },
    // Removes the new items the sidebar already shows: paid features the viewer has outside its
    // plan, such as a public project with the legacy open source license on GitLab.com. A trial
    // keeps them, since its pages show what features they are missing when the trial ends.
    withoutItemsInSidebar(page) {
      if (this.currentPlanContext.trial) return page;

      return {
        ...page,
        categories: page.categories.map((category) => ({
          ...category,
          items: category.items.filter((item) => !this.isNewItemInSidebar(item)),
        })),
      };
    },
    // Enhanced items stay, since the page shows what the plan adds to them.
    isNewItemInSidebar(item) {
      return item.label?.type === LABEL_TYPE_NEW && Boolean(this.catalogById[item.id]);
    },
    openExplorePage(plan) {
      this.activeExplorePlan = plan;
      this.trackEvent('click_explore_entry_card_in_feature_library_modal', { label: plan });
      this.trackEvent('view_explore_page_in_feature_library_modal', {
        label: plan,
        property: this.currentPlanContext.trial ? 'trial' : this.currentPlanContext.base_plan,
      });

      // The entry card that had focus is gone: the title announces the new view.
      this.$nextTick(() => this.$refs.title?.focus());
    },
    onExploreCtaClick(type) {
      this.trackEvent('click_upgrade_cta_in_feature_library_modal', {
        label: this.activeExplorePlan,
        property: type,
      });
    },
    closeExplorePage() {
      this.activeExplorePlan = null;
    },
    trackExplorePageButtonsViewed() {
      this.explorePages.forEach(({ plan }) => {
        this.trackEvent('view_explore_entry_card_in_feature_library_modal', { label: plan });
      });
    },
    focusFirstResult(event) {
      if (!this.trimmedQuery) return;

      // Move focus into the results instead of navigating away: focusing the
      // first result lets keyboard users continue from there
      // (e.g. Tab to its pin action, or Enter again to open it). When the
      // main grid is empty, fall through to the first Gemini suggestion; a
      // hidden Gemini section renders no refs, so this no-ops and both keys
      // keep their default behavior.
      const target =
        this.findResultComponent(this.$refs.searchResultItems, this.filteredItems[0]) ||
        this.findResultComponent(this.$refs.geminiResultItems, this.geminiItems[0]);

      if (!target) return;

      event.preventDefault();
      target.focus();
    },
    // Match by id rather than taking refs[0]: Vue 2's v-for ref arrays
    // reflect registration order, which isn't guaranteed to track the
    // current (re-ranked) item order.
    findResultComponent(components, item) {
      if (!item) return null;
      return (components || []).find((component) => component.item.id === item.id) || null;
    },
    revealRemainingItems() {
      if (this.renderLimit >= this.catalog.length) return;
      this.revealFrameId = window.requestAnimationFrame(() => {
        this.renderLimit += ITEMS_PER_RENDER_FRAME;
        this.revealRemainingItems();
      });
    },
    cancelReveal() {
      if (this.revealFrameId) {
        window.cancelAnimationFrame(this.revealFrameId);
        this.revealFrameId = null;
      }
    },
    resetSearchState() {
      this.isSearching = false;
      this.latestQuery = null;
      this.searchResultIds = [];
    },
    resetGeminiState() {
      this.geminiResultIds = [];
      this.isGeminiSearching = false;
      this.geminiSearched = false;
      this.geminiHidden = false;
      this.geminiErrorMessage = null;
    },
    onSearchInput(value) {
      this.searchQuery = value;
      const query = value.trim();
      this.resetGeminiState();

      if (query) {
        this.fetchResults(query);
        this.trackEvent(EVENT_SEARCH_FEATURES_IN_FEATURE_LIBRARY_MODAL);
      } else {
        this.resetSearchState();
      }
    },
    onPinToggle(itemId, nextState, title) {
      this.$emit('pin-toggle', itemId, nextState, title);
      const event = nextState
        ? EVENT_PIN_ITEM_IN_FEATURE_LIBRARY_MODAL
        : EVENT_UNPIN_ITEM_IN_FEATURE_LIBRARY_MODAL;
      this.trackEvent(event, { label: itemId });
    },
    onNavigate(itemId) {
      this.trackEvent(EVENT_NAVIGATE_TO_FEATURE_FROM_FEATURE_LIBRARY_MODAL, {
        label: itemId,
      });
    },
    onHidden() {
      this.isModalOpen = false;
      this.activeExplorePlan = null;
      this.resetSearchState();
      this.resetGeminiState();
      this.cancelReveal();
      this.searchQuery = '';
      this.selectedCategory = ALL_CATEGORIES;
      this.collapsedSectionIds = [];
      this.renderLimit = ITEMS_PER_RENDER_FRAME;
    },
    fetchResults(query) {
      if (query.length < MIN_SEARCH_QUERY_LENGTH) {
        this.resetSearchState();
        return;
      }

      this.latestQuery = query;
      this.isSearching = true;

      axios
        .get(onboardingFeatureLibrarySearchPath(), { params: { query, panel: this.panelType } })
        .then(({ data }) => {
          if (query !== this.latestQuery) return;
          this.applySearchResultIds(data.ids || []);
        })
        .catch((e) => {
          if (query !== this.latestQuery) return;
          if (e.response?.status !== HTTP_STATUS_TOO_MANY_REQUESTS) {
            Sentry.captureException(e, SENTRY_CONTEXT);
          }
          this.applySearchResultIds([]);
        })
        .finally(() => {
          if (query !== this.latestQuery) return;
          this.isSearching = false;
        });
    },
    // A kept result can hold keyboard focus while the request is in flight; if
    // the response drops it, it unmounts and focus silently falls to <body>.
    applySearchResultIds(ids) {
      const focused = document.activeElement;
      const hadFocusedResult = this.isInsideResult(focused);

      this.searchResultIds = ids;

      if (!hadFocusedResult) return;

      this.$nextTick(() => {
        if (!this.isInsideResult(focused)) this.$refs.searchBox?.focusInput?.();
      });
    },
    isInsideResult(element) {
      return (this.$refs.searchResultItems || []).some((item) => item.$el.contains(element));
    },
    async searchWithGemini() {
      if (!this.resourceId || !this.aiSearchAvailable) return;

      const query = this.trimmedQuery;
      this.trackEvent(EVENT_SEARCH_WITH_GEMINI_IN_FEATURE_LIBRARY_MODAL);
      this.geminiHidden = false;
      this.isGeminiSearching = true;
      this.geminiErrorMessage = null;

      // The "Search with Gemini" button unmounts once searching starts, which would
      // otherwise silently drop keyboard focus to <body>. Return focus to the search
      // input, which remains mounted throughout.
      this.$refs.searchBox?.focusInput?.();

      try {
        const { data } = await axios.get(onboardingFeatureLibraryAiSearchPath(), {
          params: { query, panel: this.panelType, resource_id: this.resourceId },
        });
        if (query !== this.trimmedQuery) return;
        this.geminiResultIds = data.ids || [];
        this.geminiSearched = true;
      } catch (e) {
        if (query !== this.trimmedQuery) return;

        const status = e.response?.status;
        if (status === HTTP_STATUS_TOO_MANY_REQUESTS) {
          this.geminiErrorMessage =
            e.response?.data?.error ||
            s__('FeatureLibrary|You have reached the search limit. Try again later.');
        } else {
          // Includes 404: the button is gated on aiSearchAvailable, so this
          // shouldn't normally occur; if it does (e.g. a stale flag/trial state),
          // it's unexpected and worth reporting.
          Sentry.captureException(e, SENTRY_CONTEXT);
          this.geminiErrorMessage = s__(
            'FeatureLibrary|Something went wrong searching with Gemini. Try again.',
          );
        }
      } finally {
        if (query === this.trimmedQuery) {
          this.isGeminiSearching = false;
        }
      }
    },
    hideGeminiSection() {
      this.geminiHidden = true;

      // Re-focusing as the Hide button unmounts along with the rest of the Gemini section
      this.$refs.searchBox?.focusInput?.();
    },
  },
};
</script>

<template>
  <gl-modal
    :modal-id="$options.modalId"
    :aria-label="s__('FeatureLibrary|Feature catalog')"
    :hide-footer="!showFooter"
    modal-class="feature-library-modal"
    :body-class="['gl-flex gl-flex-col gl-overflow-hidden', { '!gl-pb-0': !showFooter }]"
    size="lg"
    hide-header
    @show="onShow"
    @shown="onShown"
    @hidden="onHidden"
  >
    <div
      v-if="showExploreEntries"
      class="gl-my-4 gl-flex gl-flex-wrap gl-items-center gl-gap-x-3 gl-gap-y-4"
      data-testid="feature-library-header"
    >
      <gl-button
        v-if="activeExplorePage"
        category="tertiary"
        icon="chevron-lg-left"
        :aria-label="s__('FeatureLibrary|Back to all features')"
        data-testid="feature-library-back"
        @click="closeExplorePage"
      />
      <h2
        ref="title"
        tabindex="-1"
        class="gl-heading-3 gl-m-0 gl-grow"
        data-testid="feature-library-title"
      >
        {{ headerTitle }}
      </h2>
      <!-- The backend sends no CTA when the viewer can't purchase. -->
      <feature-library-upgrade-cta
        v-if="activeExplorePage && activeExplorePage.cta"
        class="gl-ml-8 sm:gl-ml-0"
        :cta="activeExplorePage.cta"
        @click="onExploreCtaClick"
      />
    </div>
    <div
      v-if="!activeExplorePage"
      :class="{ 'gl-mb-5 gl-mt-2 gl-flex gl-flex-col gl-gap-4': showExploreEntries }"
    >
      <gl-search-box-by-type
        ref="searchBox"
        autofocus
        :class="{ 'gl-mt-3': !showExploreEntries }"
        :value="searchQuery"
        :placeholder="searchPlaceholder"
        :aria-describedby="$options.searchInputDescriptionId"
        :debounce="$options.DEFAULT_DEBOUNCE_AND_THROTTLE_MS"
        :is-loading="isSearching"
        @input="onSearchInput"
        @keydown.enter="focusFirstResult"
        @keydown.down="focusFirstResult"
      />
      <span :id="$options.searchInputDescriptionId" class="gl-sr-only">
        {{ $options.i18n.searchInputDescription }}
      </span>
      <div
        role="group"
        :aria-label="s__('FeatureLibrary|Filter features by category')"
        data-testid="feature-library-category-filters"
        class="-gl-ml-2 gl-flex gl-shrink-0 gl-gap-2 gl-overflow-x-auto gl-p-2"
        :class="{ 'gl-mb-1 gl-mt-1': !showExploreEntries }"
      >
        <gl-button
          v-for="category in categoryOptions"
          :key="category.id"
          category="secondary"
          size="small"
          class="gl-shrink-0"
          :selected="isCategorySelected(category.id)"
          :aria-pressed="isCategorySelected(category.id) ? 'true' : 'false'"
          data-testid="feature-library-category-filter"
          @click="selectCategory(category.id)"
        >
          {{ category.title }}
        </gl-button>
      </div>
      <div
        v-if="showExploreEntries"
        class="gl-grid gl-shrink-0 gl-grid-cols-1 gl-gap-3"
        :class="{ 'sm:gl-grid-cols-2': explorePageButtons.length > 1 }"
        data-testid="feature-library-explore-page-buttons"
      >
        <feature-library-explore-page-button
          v-for="button in explorePageButtons"
          :key="button.key"
          :title="button.title"
          :subtitle="button.subtitle"
          :loading="button.loading"
          @select="openExplorePage(button.plan)"
        />
      </div>
    </div>
    <!-- Announced via a live region since focus returns to the search input,
         not the filter button, on category selection. -->
    <div
      role="status"
      aria-live="polite"
      aria-atomic="true"
      data-testid="feature-library-category-status"
      class="gl-sr-only"
    >
      {{ categoryStatusMessage }}
    </div>
    <!-- Always present in the DOM for the same mount-timing reason as the
         Gemini status region below. -->
    <div
      role="status"
      aria-live="polite"
      aria-atomic="true"
      data-testid="search-status-region"
      class="gl-sr-only"
    >
      {{ searchStatusMessage }}
    </div>
    <feature-library-explore-page v-if="activeExplorePage" :page="activeExplorePage" />
    <scroll-scrim
      v-else
      data-testid="feature-library-scroll-area"
      class="feature-library-scroll-area feature-library-scroll-bleed gl-min-h-0 gl-grow"
    >
      <div class="feature-library-scroll-inset">
        <!-- Search results or a category filter: a single flat, ranked grid. -->
        <ul
          v-if="showResultsGrid && filteredItems.length > 0"
          data-testid="feature-library-grid"
          class="gl-grid gl-list-none gl-grid-cols-1 gl-gap-3 gl-p-0 sm:gl-grid-cols-2 md:gl-grid-cols-3"
        >
          <feature-library-item
            v-for="item in filteredItems"
            :key="item.id"
            ref="searchResultItems"
            :supports-pins="supportsPins"
            :item="item"
            :pinned="isPinned(item.id)"
            @pin-toggle="onPinToggle"
            @navigate="onNavigate"
          />
        </ul>
        <!-- Browsing: features grouped by category, each in a collapsible section. -->
        <template v-else-if="showGroupedSections">
          <section
            v-for="section in groupedSections"
            :key="section.id"
            data-testid="feature-library-section"
            class="gl-mb-3"
          >
            <h3 class="gl-m-0">
              <gl-button
                category="tertiary"
                size="small"
                block
                button-text-classes="gl-flex gl-w-full gl-items-center gl-gap-2 gl-text-base gl-font-semibold gl-text-subtle"
                :aria-expanded="isSectionExpanded(section.id) ? 'true' : 'false'"
                :aria-controls="`feature-library-section-${section.id}`"
                data-testid="feature-library-section-toggle"
                @click="toggleSection(section.id)"
              >
                <span class="gl-grow gl-text-left">{{ section.title }}</span>
                <gl-icon :name="isSectionExpanded(section.id) ? 'chevron-down' : 'chevron-right'" />
              </gl-button>
            </h3>
            <gl-collapse
              :id="`feature-library-section-${section.id}`"
              :visible="isSectionExpanded(section.id)"
            >
              <ul
                data-testid="feature-library-section-grid"
                class="gl-mt-2 gl-grid gl-list-none gl-grid-cols-1 gl-gap-3 gl-p-0 sm:gl-grid-cols-2 md:gl-grid-cols-3"
              >
                <feature-library-item
                  v-for="item in section.items"
                  :key="item.id"
                  :supports-pins="supportsPins"
                  :item="item"
                  :pinned="isPinned(item.id)"
                  @pin-toggle="onPinToggle"
                  @navigate="onNavigate"
                />
              </ul>
            </gl-collapse>
          </section>
        </template>
        <gl-loading-icon
          v-if="isSearching && filteredItems.length === 0"
          size="sm"
          class="gl-mt-3"
          data-testid="search-loading"
        />
        <gl-empty-state
          v-if="showEmptyState"
          :title="emptyStateTitle"
          :description="s__('FeatureLibrary|Try a different search term.')"
        />
        <!-- Always present in the DOM (not gated by showGeminiSection) so screen
             readers pick up the *first* content change: a live region that enters
             the DOM with content already set is not reliably announced. -->
        <div
          role="status"
          aria-live="polite"
          aria-atomic="true"
          data-testid="gemini-status-region"
          class="gl-sr-only"
        >
          {{ geminiStatusMessage }}
        </div>
        <template v-if="showGeminiSection">
          <div data-testid="gemini-section" :class="{ 'gl-border-t': showGeminiTopBorder }">
            <div v-if="showGeminiHeader" class="gl-flex gl-items-center gl-justify-between gl-py-4">
              <h3 class="gl-m-0 gl-text-base gl-font-bold">
                <gl-icon name="tanuki-ai" :size="16" class="gl-mr-2" />
                {{ s__('FeatureLibrary|Suggested by Gemini') }}
              </h3>
              <gl-button
                category="tertiary"
                size="small"
                data-testid="hide-gemini-section"
                @click="hideGeminiSection"
              >
                {{ s__('FeatureLibrary|Hide') }}
              </gl-button>
            </div>
            <div
              v-if="isGeminiSearching || geminiErrorMessage || showGeminiEmptyState"
              class="gl-flex gl-items-center gl-justify-center gl-gap-3 gl-py-5 gl-text-subtle"
            >
              <template v-if="isGeminiSearching">
                <gl-loading-icon size="sm" aria-hidden="true" data-testid="gemini-loading" />
                <span aria-hidden="true">{{ $options.i18n.geminiSearching }}</span>
              </template>
              <span v-else-if="geminiErrorMessage" aria-hidden="true" data-testid="gemini-error">
                {{ geminiErrorMessage }}
              </span>
              <span v-else aria-hidden="true" data-testid="gemini-empty-state">
                {{ $options.i18n.geminiEmptyState }}
              </span>
            </div>
            <ul
              v-if="geminiItems.length > 0"
              data-testid="gemini-results-grid"
              class="gl-grid gl-list-none gl-grid-cols-1 gl-gap-3 gl-p-0 sm:gl-grid-cols-2 md:gl-grid-cols-3"
            >
              <feature-library-item
                v-for="item in geminiItems"
                :key="item.id"
                ref="geminiResultItems"
                :item="item"
                :pinned="isPinned(item.id)"
                @pin-toggle="onPinToggle"
                @navigate="onNavigate"
              />
            </ul>
            <p v-if="geminiItems.length > 0" class="gl-mb-0 gl-text-subtle">
              {{ s__('FeatureLibrary|Recommended based on your search') }}
            </p>
          </div>
        </template>
      </div>
    </scroll-scrim>
    <template #modal-footer>
      <div class="gl-m-0 gl-flex gl-w-full gl-flex-col gl-gap-4">
        <gl-button
          v-if="showGeminiButton"
          class="feature-library-gemini-button"
          block
          data-testid="search-with-gemini-button"
          :button-text-classes="['gl-flex', 'gl-justify-between', 'gl-w-full']"
          @click="searchWithGemini"
        >
          <span class="gl-my-3">
            {{ s__("FeatureLibrary|Can't find what you're looking for? Search with AI") }}
          </span>
          <span class="gl-my-3 gl-text-sm">
            <gl-icon name="tanuki-ai" :size="16" />
            <span>{{ s__('FeatureLibrary|Powered by Gemini') }}</span>
          </span>
        </gl-button>
      </div>
    </template>
  </gl-modal>
</template>
