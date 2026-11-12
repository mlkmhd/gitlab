<script>
import { FIELD_TYPES } from '../../constants';
import { baseFieldKeyOf } from '../../utils/chart_data';
import FieldPresenter from './field.vue';
import { dimensionNullLabelOf } from './utils/dimension_null_label';
import { NO_VALUE } from './utils/stat';

export default {
  name: 'TableCellPresenter',
  components: {
    FieldPresenter,
  },
  props: {
    item: {
      required: true,
      type: Object,
    },
    field: {
      required: true,
      type: Object,
    },
    source: {
      required: false,
      type: String,
      default: '',
    },
    // Cuts the value off at the column's edge, for a column with a fixed width.
    truncate: {
      required: false,
      type: Boolean,
      default: false,
    },
  },
  computed: {
    // A metric the user may not read comes back null, not as an error; "None" would read as zero.
    isMetricWithoutValue() {
      return this.field.type === FIELD_TYPES.METRIC && this.item[this.field.key] == null;
    },
    // A null group or project dimension is a real bucket, not a missing value.
    dimensionNullLabel() {
      return dimensionNullLabelOf(this.field, this.item, this.source);
    },
  },
  methods: {
    baseFieldKeyOf,
    // Native title, and only when the text is cut off. Project cells never overflow this wrapper:
    // their avatar link truncates its own name and carries the full name as its title.
    titleIfTruncated({ currentTarget: cell }) {
      // eslint-disable-next-line no-param-reassign
      cell.title = cell.scrollWidth > cell.clientWidth ? cell.textContent.trim() : '';
    },
  },
  NO_VALUE,
};
</script>
<template>
  <span v-if="isMetricWithoutValue" class="gl-text-subtle" data-testid="metric-no-value">
    {{ $options.NO_VALUE }}
  </span>
  <div v-else-if="dimensionNullLabel" class="gl-text-subtle" data-testid="dimension-no-value">
    {{ dimensionNullLabel.text }}
    <div v-if="dimensionNullLabel.hint" class="gl-text-sm" data-testid="dimension-no-value-hint">
      {{ dimensionNullLabel.hint }}
    </div>
  </div>
  <div
    v-else-if="truncate"
    class="gl-truncate [&_a>span:last-child]:gl-truncate [&_a]:gl-max-w-full"
    data-testid="truncated-cell"
    @mouseenter="titleIfTruncated"
  >
    <field-presenter
      :item="item"
      :field-key="field.key"
      :presenter-key="baseFieldKeyOf(field)"
      :parameters="field.parameters"
    />
  </div>
  <field-presenter
    v-else
    :item="item"
    :field-key="field.key"
    :presenter-key="baseFieldKeyOf(field)"
    :parameters="field.parameters"
  />
</template>
