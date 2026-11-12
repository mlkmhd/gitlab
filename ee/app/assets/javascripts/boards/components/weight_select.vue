<script>
import { GlCollapsibleListbox, GlButton } from '@gitlab/ui';
import { s__ } from '~/locale';

// Values from the backend (Issue::WEIGHT_ANY and Issue::WEIGHT_NONE), not display text
const ANY_WEIGHT_VALUE = 'Any';
const NO_WEIGHT_VALUE = 'None';
const NO_WEIGHT = -2;

export default {
  name: 'WeightSelect',
  components: {
    GlButton,
    GlCollapsibleListbox,
  },
  props: {
    board: {
      type: Object,
      required: true,
    },
    canEdit: {
      type: Boolean,
      required: false,
      default: false,
    },
    weights: {
      type: Array,
      required: true,
    },
  },
  emits: ['set-weight'],
  data() {
    return {
      dropdownHidden: true,
      selected: this.board.weight,
    };
  },
  computed: {
    listBoxItems() {
      return this.weights.map((item) => ({ value: item, text: this.weightItemText(item) }));
    },
    valueClass() {
      return this.valueText === this.$options.i18n.anyWeight ? 'gl-text-subtle' : 'bold';
    },
    valueText() {
      const weight = this.selected;
      if (weight > 0 || weight === 0) return weight.toString();
      if (weight === NO_WEIGHT) return this.$options.i18n.noWeight;
      return this.$options.i18n.anyWeight;
    },
  },
  methods: {
    showDropdown() {
      this.dropdownHidden = false;

      this.$nextTick(() => {
        this.$refs.dropdown.open();
      });
    },
    selectWeight(rawWeight) {
      const weight = this.weightInt(rawWeight);
      this.selected = weight;
      this.dropdownHidden = true;
      this.$emit('set-weight', weight);
    },
    weightItemText(item) {
      if (item === NO_WEIGHT_VALUE) return this.$options.i18n.noWeight;
      if (item === ANY_WEIGHT_VALUE) return this.$options.i18n.any;
      return String(item);
    },
    weightInt(weight) {
      if (weight >= 0) {
        return weight;
      }
      if (weight === NO_WEIGHT_VALUE) {
        return NO_WEIGHT;
      }
      return null;
    },
    toggleEdit() {
      if (this.dropdownHidden) {
        this.showDropdown();
      } else {
        this.dropdownHidden = true;
      }
    },
  },
  i18n: {
    label: s__('BoardScope|Weight'),
    edit: s__('BoardScope|Edit'),
    anyWeight: s__('BoardScope|Any weight'),
    noWeight: s__('BoardScope|None'),
    any: s__('BoardScope|Any'),
  },
};
</script>

<template>
  <div class="block weight">
    <div class="title gl-mb-3">
      {{ $options.i18n.label }}
      <gl-button
        v-if="canEdit"
        category="tertiary"
        size="small"
        class="edit-link gl-float-right"
        @click="toggleEdit"
      >
        {{ $options.i18n.edit }}
      </gl-button>
    </div>
    <div v-if="dropdownHidden" :class="valueClass" data-testid="selected-weight">
      {{ valueText }}
    </div>

    <gl-collapsible-listbox
      v-if="!dropdownHidden"
      ref="dropdown"
      block
      toggle-class="gl-w-full"
      :items="listBoxItems"
      :selected="selected"
      :toggle-text="valueText"
      @select="selectWeight"
    />
  </div>
</template>
