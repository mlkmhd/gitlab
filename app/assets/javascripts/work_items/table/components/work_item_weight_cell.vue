<script>
import { findWeightWidget } from '../../utils';
import { EDIT_TRIGGER_CELL } from '../constants';
import CellTextEditor from './editable_cell/cell_text_editor.vue';
import WorkItemEditableCell from './editable_cell/work_item_editable_cell.vue';

export default {
  name: 'WorkItemWeightCell',
  components: {
    CellTextEditor,
    WorkItemEditableCell,
  },
  props: {
    item: {
      type: Object,
      required: true,
    },
  },
  computed: {
    canEdit() {
      return Boolean(findWeightWidget(this.item));
    },
    weight() {
      return findWeightWidget(this.item)?.weight;
    },
    displayWeight() {
      return this.weight ?? '';
    },
  },
  methods: {
    isValidWeight(editedValue) {
      if (editedValue === null || editedValue === '') return true;
      const num = parseInt(editedValue, 10);
      return !Number.isNaN(num) && num >= 0 && String(num) === String(editedValue).trim();
    },
    weightInput(editedValue) {
      const isEmpty = editedValue === '' || editedValue === null;
      const weight = isEmpty ? null : parseInt(editedValue, 10);
      return weight === this.weight ? null : { weightWidget: { weight } };
    },
  },
  EDIT_TRIGGER_CELL,
};
</script>

<template>
  <work-item-editable-cell
    :item="item"
    :can-edit="canEdit"
    :edit-trigger="$options.EDIT_TRIGGER_CELL"
    :saving-text="s__('WorkItem|Saving weight')"
    :error-message="s__('WorkItem|Something went wrong while updating the weight.')"
    class="gl-w-full gl-px-4 gl-py-2"
    data-testid="cell-weight"
  >
    <template #display>
      <span :class="{ 'gl-h-5': displayWeight === '' }" data-testid="weight-value">{{
        displayWeight
      }}</span>
    </template>

    <template #editor="{ save, cancel, isSaving }">
      <cell-text-editor
        :value="weight"
        :is-saving="isSaving"
        :validator="isValidWeight"
        :aria-label="s__('WorkItem|Weight')"
        type="number"
        min="0"
        step="1"
        select-on-focus
        cancel-invalid-on-blur
        data-testid="weight-input"
        @submit="save(weightInput($event))"
        @cancel="cancel"
      />
    </template>
  </work-item-editable-cell>
</template>
