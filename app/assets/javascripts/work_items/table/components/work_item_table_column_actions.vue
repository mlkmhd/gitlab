<script>
import { GlDisclosureDropdown } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import { COLUMN_DIRECTION } from '../constants';

export default {
  name: 'WorkItemTableColumnActions',
  components: {
    GlDisclosureDropdown,
  },
  props: {
    columnLabel: {
      type: String,
      required: true,
    },
    canMoveLeft: {
      type: Boolean,
      required: false,
      default: false,
    },
    canMoveRight: {
      type: Boolean,
      required: false,
      default: false,
    },
    canHide: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['move-column', 'hide-column'],
  computed: {
    toggleText() {
      return sprintf(s__('WorkItem|%{columnName} column options'), {
        columnName: this.columnLabel,
      });
    },
    actionItems() {
      const items = [];
      if (this.canHide) {
        items.push({
          text: s__('WorkItem|Hide field'),
          icon: 'eye-slash',
          action: () => this.$emit('hide-column'),
        });
      }
      if (this.canMoveLeft) {
        items.push({
          text: s__('WorkItem|Move left'),
          icon: 'arrow-left',
          action: () => this.$emit('move-column', COLUMN_DIRECTION.LEFT),
        });
      }
      if (this.canMoveRight) {
        items.push({
          text: s__('WorkItem|Move right'),
          icon: 'arrow-right',
          action: () => this.$emit('move-column', COLUMN_DIRECTION.RIGHT),
        });
      }
      return items;
    },
    groups() {
      return [{ name: s__('WorkItem|Column options'), items: this.actionItems }];
    },
  },
};
</script>

<template>
  <gl-disclosure-dropdown
    v-if="actionItems.length"
    :items="groups"
    :toggle-text="toggleText"
    icon="ellipsis_v"
    category="tertiary"
    size="small"
    placement="bottom-end"
    no-caret
    text-sr-only
    data-testid="table-column-actions"
  />
</template>
