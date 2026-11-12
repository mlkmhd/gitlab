<script>
import { GlButton, GlCollapsibleListbox, GlFilteredSearchToken, GlIcon } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import {
  REPOSITORIES_OPTIONAL_COLUMNS,
  REPOSITORIES_TABLE_FIELDS,
  REPOSITORY_FORMAT_ALL,
  REPOSITORY_FORMAT_FILTER_OPTIONS,
  REPOSITORY_FORMAT_LOGO_SIZE_LISTBOX,
  REPOSITORY_KIND_LABELS,
} from 'ee/packages_and_registries/artifact_registry/constants';
import FormatLogo from 'ee/packages_and_registries/artifact_registry/repositories/components/format_logo.vue';
import ViewOptions from 'ee/packages_and_registries/artifact_registry/repositories/components/view_options.vue';
import { s__ } from '~/locale';
import { OPERATOR_IS, OPERATORS_IS } from '~/vue_shared/components/filtered_search_bar/constants';
import FilteredSearchBarRoot from '~/vue_shared/components/filtered_search_bar/filtered_search_bar_root.vue';

const REPOSITORY_KIND_TOKEN_TYPE = 'kind';

// Type is the only token the list endpoint supports
const REPOSITORY_KIND_TOKEN = {
  type: REPOSITORY_KIND_TOKEN_TYPE,
  title: s__('ArtifactRegistry|Type'),
  token: GlFilteredSearchToken,
  unique: true,
  operators: OPERATORS_IS,
  options: Object.entries(REPOSITORY_KIND_LABELS).map(([value, title]) => ({ value, title })),
};

export default {
  name: 'ArtifactRegistryRepositoriesToolbar',
  components: {
    FilteredSearchBarRoot,
    FormatLogo,
    GlButton,
    GlCollapsibleListbox,
    GlIcon,
    ViewOptions,
  },
  inject: ['organizationGid'],
  props: {
    filters: {
      type: Object,
      required: true,
    },
    hiddenColumns: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  emits: ['apply-filter', 'hidden-columns-changed'],
  data() {
    return {
      formatLabelId: uniqueId('artifact-registry-format-filter-'),
    };
  },
  computed: {
    selectedFormat() {
      return this.filters.format ?? REPOSITORY_FORMAT_ALL;
    },
    selectedFormatLabel() {
      return REPOSITORY_FORMAT_FILTER_OPTIONS.find(({ value }) => value === this.selectedFormat)
        ?.text;
    },
    initialFilterValue() {
      if (!this.filters.kind) {
        return [];
      }

      return [
        {
          type: REPOSITORY_KIND_TOKEN_TYPE,
          value: { data: this.filters.kind, operator: OPERATOR_IS },
        },
      ];
    },
  },
  methods: {
    hasLogo(format) {
      return format !== REPOSITORY_FORMAT_ALL;
    },
    selectFormat(format) {
      this.$emit('apply-filter', {
        ...this.filters,
        format: format === REPOSITORY_FORMAT_ALL ? null : format,
      });
    },
    applyTokens(tokens) {
      // The bar also emits the free-text term it collects, which the list endpoint does
      // not honor, so only the Type token reaches the filters.
      const kindToken = tokens.find(({ type }) => type === REPOSITORY_KIND_TOKEN_TYPE);
      const kind = kindToken?.value?.data ?? null;

      this.$emit('apply-filter', { ...this.filters, kind });
    },
  },
  formatOptions: REPOSITORY_FORMAT_FILTER_OPTIONS,
  logoSize: REPOSITORY_FORMAT_LOGO_SIZE_LISTBOX,
  tokens: [REPOSITORY_KIND_TOKEN],
  optionalColumns: REPOSITORIES_TABLE_FIELDS.filter(({ key }) =>
    REPOSITORIES_OPTIONAL_COLUMNS.includes(key),
  ),
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-3 gl-border-y-0 gl-bg-subtle gl-p-5 @md/panel:gl-flex-row">
    <!-- `sync-filter-and-sort` ungates the bar's re-sync watcher, without which a
         selection the bar did not raise never reaches its rendered tokens.
         `search-text-option-label` only shows when `terms-as-tokens` is set. -->
    <filtered-search-bar-root
      class="gl-min-w-0 gl-grow"
      :namespace="organizationGid"
      :tokens="$options.tokens"
      :initial-filter-value="initialFilterValue"
      :search-input-placeholder="s__('ArtifactRegistry|Filter repositories by type')"
      :search-text-option-label="s__('ArtifactRegistry|Raw text search not supported')"
      terms-as-tokens
      sync-filter-and-sort
      @on-filter="applyTokens"
    />

    <view-options
      :columns="$options.optionalColumns"
      :hidden-columns="hiddenColumns"
      @input="$emit('hidden-columns-changed', $event)"
    />

    <span :id="formatLabelId" class="gl-sr-only">{{ s__('ArtifactRegistry|Format') }}</span>
    <gl-collapsible-listbox
      :items="$options.formatOptions"
      :selected="selectedFormat"
      :toggle-text="selectedFormatLabel"
      :toggle-aria-labelled-by="formatLabelId"
      @select="selectFormat"
    >
      <template #toggle="{ accessibilityAttributes }">
        <gl-button
          class="gl-new-dropdown-toggle gl-h-full"
          button-text-classes="gl-flex gl-w-full gl-items-center"
          v-bind="accessibilityAttributes"
        >
          <format-logo
            v-if="hasLogo(selectedFormat)"
            :format="selectedFormat"
            :size="$options.logoSize"
            class="gl-mr-3"
            data-testid="format-filter-toggle-logo"
          />
          <span class="gl-grow gl-text-left">{{ selectedFormatLabel }}</span>
          <gl-icon name="chevron-down" class="gl-button-icon gl-new-dropdown-chevron" />
        </gl-button>
      </template>
      <template #list-item="{ item }">
        <span class="gl-flex gl-items-center gl-gap-3">
          <format-logo
            v-if="hasLogo(item.value)"
            :format="item.value"
            :size="$options.logoSize"
            data-testid="format-filter-logo"
          />
          {{ item.text }}
        </span>
      </template>
    </gl-collapsible-listbox>
  </div>
</template>
