<script>
import { GlIcon, GlSkeletonLoader } from '@gitlab/ui';
import { sortBy } from '../../core/sorter';
import { labelWithParameter } from '../../utils/chart_data';
import ThResizable from '../common/th_resizable.vue';
import TableCell from './table_cell.vue';
import { listDescriptionError, listDescriptionFor } from './utils/description';
import { columnWidthOf, columnWidthsError } from './utils/column_widths';
import { hiddenMetricsError, visibleFieldsOf } from './utils/hidden_metrics';

const DEFAULT_PAGE_SIZE = 5;

export default {
  name: 'TablePresenter',
  components: {
    GlIcon,
    GlSkeletonLoader,
    ThResizable,
    TableCell,
  },
  inject: {
    getVisualizationTitle: { default: () => () => '' },
  },
  props: {
    data: {
      required: false,
      type: Object,
      default: () => ({ nodes: [] }),
    },
    fields: {
      required: false,
      type: Array,
      default: () => [],
    },
    loading: {
      required: false,
      type: [Boolean, Number],
      default: false,
    },
    displayConfig: {
      required: false,
      type: Object,
      default: () => ({}),
    },
    source: {
      required: false,
      type: String,
      default: '',
    },
  },
  emits: { error: null },
  data() {
    return {
      items: [],
      sortOptions: { fieldName: null, ascending: true },
    };
  },
  computed: {
    visualizationTitle() {
      return this.getVisualizationTitle();
    },
    pageSize() {
      return typeof this.loading === 'number' ? this.loading : DEFAULT_PAGE_SIZE;
    },
    description() {
      return listDescriptionFor({
        description: this.displayConfig?.description,
        fields: this.fields,
        data: this.data,
        loading: this.loading,
      });
    },
    widthsError() {
      return columnWidthsError(this.displayConfig?.columnWidths, this.fields);
    },
    validationError() {
      const descriptionError = listDescriptionError(this.displayConfig?.description, this.fields);
      if (descriptionError) return descriptionError;

      return hiddenMetricsError(this.displayConfig?.hiddenMetrics, this.fields) ?? this.widthsError;
    },
    rows() {
      return this.data.nodes;
    },
    // A fixed layout keeps column boundaries in place when the rows change, as on a page turn.
    hasColumnWidths() {
      return this.displayConfig?.columnWidths != null && !this.widthsError;
    },
    columns() {
      return visibleFieldsOf(this.fields, this.displayConfig?.hiddenMetrics);
    },
  },
  watch: {
    rows: {
      immediate: true,
      handler(rows) {
        this.items = rows.slice();
      },
    },
    validationError: {
      immediate: true,
      handler(message) {
        if (message) this.$emit('error', new Error(message));
      },
    },
  },
  methods: {
    labelWithParameter,
    columnWidthOf(field) {
      return this.hasColumnWidths ? columnWidthOf(this.displayConfig.columnWidths, field) : null;
    },
    headerStyle(field) {
      const width = this.columnWidthOf(field);
      return width ? { width: `${width}%` } : undefined;
    },
    // A derived column renders one key but sorts by another.
    sortKeyOf(field) {
      return field.sortKey ?? field.key;
    },
    sortBy(field) {
      if (field.sortable === false) return;

      const { options, items } = sortBy(this.items, this.sortKeyOf(field), this.sortOptions);
      this.items = items;
      this.sortOptions = options;
    },
  },
};
</script>
<template>
  <div>
    <p v-if="description" class="gl-mb-3 gl-px-5 gl-pt-3 gl-text-subtle" data-testid="description">
      {{ description }}
    </p>
    <!-- Set from the wrapper: editing the table tag re-flags it in the Pajamas adoption scan. -->
    <div
      class="gl-table-shadow"
      :class="{ '[&>table]:gl-w-full [&>table]:gl-table-fixed': hasColumnWidths }"
      data-print-scale-container
    >
      <table class="!gl-my-0 gl-min-w-full gl-overflow-y-hidden" data-print-scale-target>
        <caption v-if="visualizationTitle" class="gl-sr-only" data-testid="table-caption">
          {{
            visualizationTitle
          }}
        </caption>
        <thead class="!gl-border-b gl-text-sm">
          <tr>
            <th-resizable
              v-for="(field, fieldIndex) in columns"
              :key="field.key"
              :style="headerStyle(field)"
              class="gl-relative !gl-bg-default !gl-p-0 !gl-text-subtle dark:!gl-bg-strong"
            >
              <div
                :data-testid="`column-${fieldIndex}`"
                class="gl-l-0 gl-r-0 gl-absolute gl-w-full gl-cursor-pointer gl-truncate gl-bg-default gl-px-5 gl-py-3 hover:gl-bg-subtle"
                @click="sortBy(field)"
              >
                {{ labelWithParameter(field) }}
                <gl-icon
                  v-if="sortOptions.fieldName === sortKeyOf(field)"
                  :name="sortOptions.ascending ? 'arrow-up' : 'arrow-down'"
                />
              </div>
              <div class="gl-pointer-events-none gl-py-3">&nbsp;</div>
            </th-resizable>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="(item, itemIndex) in items"
            :key="item.id"
            :data-testid="`table-row-${itemIndex}`"
          >
            <td
              v-for="field in columns"
              :key="field.key"
              class="!gl-border-l-0 !gl-border-r-0 gl-bg-default !gl-px-5 !gl-py-3"
            >
              <table-cell
                :item="item"
                :field="field"
                :source="source"
                :truncate="Boolean(columnWidthOf(field))"
              />
            </td>
          </tr>
          <template v-if="loading">
            <tr v-for="i in pageSize" :key="i">
              <td
                v-for="field in columns"
                :key="field.key"
                class="!gl-border-l-0 !gl-border-r-0 !gl-border-t-0 gl-bg-default !gl-px-5 !gl-py-3"
              >
                <gl-skeleton-loader :width="60" :lines="1" :equal-width-lines="true" />
              </td>
            </tr>
          </template>
        </tbody>
      </table>
    </div>
  </div>
</template>
