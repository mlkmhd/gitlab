<script>
import { GlIcon, GlSkeletonLoader } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { n__, s__, sprintf } from '~/locale';
import RowDisclosureToggle from '~/vue_shared/components/expandable_rows/row_disclosure_toggle.vue';
import { flattenTree, rowDomId, sortTree } from '~/vue_shared/components/expandable_rows/utils';
import { FIELD_TYPES } from '../../constants';
import { sortBy, sorterFor } from '../../core/sorter';
import { dimensionValue, labelWithParameter } from '../../utils/chart_data';
import ThResizable from '../common/th_resizable.vue';
import TableCell from './table_cell.vue';
import { columnWidthOf, columnWidthsError } from './utils/column_widths';
import { listDescriptionError, listDescriptionFor } from './utils/description';
import { dimensionNullLabelOf } from './utils/dimension_null_label';
import { CHILD_ROWS_KEY, ROW_KEY } from './utils/expandable_table';
import { hiddenMetricsError, visibleFieldsOf } from './utils/hidden_metrics';
import { TREND_KEY } from './utils/trend';

const DEFAULT_PAGE_SIZE = 5;

const childrenOf = (node) => node[CHILD_ROWS_KEY] ?? [];
const withChildren = (node, children) => ({ ...node, [CHILD_ROWS_KEY]: children });

/**
 * A table whose rows expand to show the rows nested under them. Each row of `data` carries its
 * key and its children, as `withBreakdown` joins them.
 */
export default {
  name: 'ExpandableTablePresenter',
  components: {
    GlIcon,
    GlSkeletonLoader,
    RowDisclosureToggle,
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
    /**
     * The dimension child rows show in the first column, or null until they have loaded.
     */
    childDimension: {
      required: false,
      type: Object,
      default: null,
    },
    childrenLoading: {
      required: false,
      type: Boolean,
      default: false,
    },
    childrenError: {
      required: false,
      type: Boolean,
      default: false,
    },
    /**
     * How many child rows loaded when they stopped short of their total, or null when every
     * one did.
     */
    truncatedChildCount: {
      required: false,
      type: Number,
      default: null,
    },
  },
  emits: { error: null, 'load-children': null },
  data() {
    return {
      sortOptions: { fieldName: null, ascending: true },
      expandedKeys: [],
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
    // A fixed layout keeps column boundaries in place when the rows change, as on a page turn
    // or when rows expand.
    hasColumnWidths() {
      return this.displayConfig?.columnWidths != null && !this.widthsError;
    },
    columns() {
      return visibleFieldsOf(this.fields, this.displayConfig?.hiddenMetrics);
    },
    tree() {
      const { fieldName, ascending } = this.sortOptions;
      if (!fieldName) return this.data.nodes;

      const compare = sorterFor(fieldName, ascending);
      // Child rows show the breakdown's dimension in the first column, so they sort by it there.
      const sortsFirstColumn = this.childDimension && fieldName === this.sortKeyOf(this.columns[0]);
      const childCompare = sortsFirstColumn
        ? sorterFor(this.sortKeyOf(this.childDimension), ascending)
        : compare;

      return sortTree(this.data.nodes, compare, {
        childrenOf,
        withChildren,
        compareAt: (depth) => (depth === 0 ? compare : childCompare),
      });
    },
    childrenTruncatedMessage() {
      if (this.truncatedChildCount == null) return null;

      return sprintf(
        n__(
          'Glql|Some nested rows are missing: only the first %{count} row could be loaded.',
          'Glql|Some nested rows are missing: only the first %{count} rows could be loaded.',
          this.truncatedChildCount,
        ),
        { count: this.truncatedChildCount },
      );
    },
    visibleRows() {
      return flattenTree(this.tree, {
        keyOf: (node) => node[ROW_KEY] ?? null,
        childrenOf,
        // Every parent keeps its toggle, even once its children show it has none: swapping the
        // toggle out would drop keyboard focus from it.
        isExpandable: (node) => node[ROW_KEY] != null && CHILD_ROWS_KEY in node,
        expandedKeys: new Set(this.expandedKeys),
      });
    },
    // Each row's toggle label by key, so a child row can tell screen readers its parent.
    toggleLabelsByKey() {
      return new Map(this.visibleRows.map((row) => [row.key, this.toggleLabel(row)]));
    },
  },
  watch: {
    validationError: {
      immediate: true,
      handler(message) {
        if (message) this.$emit('error', new Error(message));
      },
    },
  },
  created() {
    // Not reactive: only a prefix for the DOM ids the toggles point at.
    this.rowIdPrefix = uniqueId('glql-table-row-');
  },
  methods: {
    labelWithParameter,
    // Child rows take the width of the column they sit in, so this is by column, not cell field.
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

      this.sortOptions = sortBy([], this.sortKeyOf(field), this.sortOptions).options;
    },
    // A child row shows the dimension it adds in the first column, and leaves the parent's
    // other dimensions blank so they don't repeat on every child. It has no previous period, so
    // its trend cell stays blank too rather than reading as missing data.
    cellField(row, field, fieldIndex) {
      if (row.depth === 0) return field;
      if (fieldIndex === 0) return this.childDimension;
      if (field.type === FIELD_TYPES.DIMENSION || field.key === TREND_KEY) return null;

      return field;
    },
    rowKeyOf(row, rowIndex) {
      return row.key ?? row.node.id ?? `row-${rowIndex}`;
    },
    rowDomIdOf(row) {
      return row.depth > 0 && row.key != null ? rowDomId(this.rowIdPrefix, row.key) : null;
    },
    toggleLabel(row) {
      const [field] = this.columns;

      return (
        dimensionNullLabelOf(field, row.node, this.source)?.text ?? dimensionValue(row.node, field)
      );
    },
    parentLabel(row) {
      return row.parentKey == null ? '' : String(this.toggleLabelsByKey.get(row.parentKey) ?? '');
    },
    childRowIds(row) {
      return row.childKeys
        .filter((key) => key != null)
        .map((key) => rowDomId(this.rowIdPrefix, key));
    },
    toggleRow(row) {
      if (row.expanded) {
        this.expandedKeys = this.expandedKeys.filter((key) => key !== row.key);
        return;
      }

      this.expandedKeys = [...this.expandedKeys, row.key];
      if (!this.childDimension) this.$emit('load-children');
    },
    isLoadingChildren(row) {
      return row.expanded && this.childrenLoading;
    },
    hasChildrenError(row) {
      return row.expanded && !this.childrenLoading && this.childrenError;
    },
    hasNoChildren(row) {
      return row.expanded && Boolean(this.childDimension) && row.childKeys.length === 0;
    },
    noChildrenMessage() {
      // Past the row cap, a parent's children may exist but not have loaded.
      return this.truncatedChildCount == null
        ? s__('Glql|No rows under this one.')
        : s__('Glql|Rows under this one may be missing.');
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
          <template v-for="(row, rowIndex) in visibleRows">
            <tr
              :id="rowDomIdOf(row)"
              :key="rowKeyOf(row, rowIndex)"
              :data-testid="`table-row-${rowIndex}`"
            >
              <td
                v-for="(field, fieldIndex) in columns"
                :key="field.key"
                class="!gl-border-l-0 !gl-border-r-0 gl-bg-default !gl-px-5 !gl-py-3"
              >
                <row-disclosure-toggle
                  v-if="fieldIndex === 0"
                  :label="toggleLabel(row)"
                  :expandable="row.expandable"
                  :expanded="row.expanded"
                  :depth="row.depth"
                  :parent-label="parentLabel(row)"
                  :child-row-ids="childRowIds(row)"
                  :loading="isLoadingChildren(row)"
                  @toggle="toggleRow(row)"
                >
                  <table-cell
                    :item="row.node"
                    :field="cellField(row, field, fieldIndex)"
                    :source="source"
                    :truncate="Boolean(columnWidthOf(field))"
                  />
                </row-disclosure-toggle>
                <table-cell
                  v-else-if="cellField(row, field, fieldIndex)"
                  :item="row.node"
                  :field="cellField(row, field, fieldIndex)"
                  :source="source"
                  :truncate="Boolean(columnWidthOf(field))"
                />
              </td>
            </tr>
            <tr
              v-if="isLoadingChildren(row)"
              :key="`${rowKeyOf(row, rowIndex)}-loading`"
              data-gfm-ignore
              data-testid="child-rows-loading"
            >
              <td
                v-for="field in columns"
                :key="field.key"
                class="!gl-border-l-0 !gl-border-r-0 gl-bg-default !gl-px-5 !gl-py-3"
              >
                <gl-skeleton-loader :width="60" :lines="1" :equal-width-lines="true" />
              </td>
            </tr>
            <tr
              v-else-if="hasChildrenError(row)"
              :key="`${rowKeyOf(row, rowIndex)}-error`"
              data-gfm-ignore
              data-testid="child-rows-error"
            >
              <td
                :colspan="columns.length"
                class="!gl-border-l-0 !gl-border-r-0 gl-bg-default !gl-px-5 !gl-py-3 gl-text-subtle"
              >
                {{ s__('Glql|Could not load the rows under this one. Expand it again to retry.') }}
              </td>
            </tr>
            <tr
              v-else-if="hasNoChildren(row)"
              :key="`${rowKeyOf(row, rowIndex)}-empty`"
              data-gfm-ignore
              data-testid="child-rows-empty"
            >
              <td
                :colspan="columns.length"
                class="!gl-border-l-0 !gl-border-r-0 gl-bg-default !gl-px-5 !gl-py-3 gl-text-subtle"
              >
                {{ noChildrenMessage() }}
              </td>
            </tr>
          </template>
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
    <p
      v-if="childrenTruncatedMessage"
      class="gl-mb-0 gl-px-5 gl-py-3 gl-text-sm gl-text-subtle"
      data-testid="child-rows-truncated"
    >
      {{ childrenTruncatedMessage }}
    </p>
  </div>
</template>
