<script>
import { GlButton, GlLoadingIcon, GlToastMixin } from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { EDIT_TRIGGER_BUTTON, EDIT_TRIGGER_CELL } from '../../constants';
import { updateWorkItemField } from '../../utils';

export default {
  name: 'WorkItemEditableCell',
  components: {
    GlButton,
    GlLoadingIcon,
  },
  mixins: [GlToastMixin],
  props: {
    item: {
      type: Object,
      required: true,
    },
    canEdit: {
      type: Boolean,
      required: false,
      default: true,
    },
    editTrigger: {
      type: String,
      required: false,
      default: EDIT_TRIGGER_BUTTON,
      validator: (value) => [EDIT_TRIGGER_BUTTON, EDIT_TRIGGER_CELL].includes(value),
    },
    editLabel: {
      type: String,
      required: false,
      default: '',
    },
    savingText: {
      type: String,
      required: false,
      default: '',
    },
    errorMessage: {
      type: String,
      required: true,
    },
  },
  emits: ['cell-click'],
  data() {
    return {
      isEditing: false,
      isSaving: false,
    };
  },
  computed: {
    hasEditButton() {
      return this.canEdit && this.editTrigger === EDIT_TRIGGER_BUTTON;
    },
    startsOnCellClick() {
      return this.canEdit && this.editTrigger === EDIT_TRIGGER_CELL;
    },
  },
  methods: {
    handleClick(event) {
      if (this.isEditing) return;

      if (this.startsOnCellClick) {
        this.startEditing();
      } else {
        this.$emit('cell-click', event);
      }
    },
    startEditing() {
      if (!this.canEdit) return;
      this.isEditing = true;
    },
    stopEditing() {
      if (!this.isEditing) return;

      this.isEditing = false;
      this.$nextTick(() => {
        this.$refs.editButton?.$el?.focus();
      });
    },
    async save(input) {
      if (!this.isEditing || this.isSaving) return false;

      if (!input) {
        this.stopEditing();
        return true;
      }

      this.isSaving = true;

      try {
        await updateWorkItemField(this.$apollo, {
          id: this.item.id,
          input,
          useWorkItemFeatures: true,
        });
        this.stopEditing();
        return true;
      } catch (error) {
        this.$toast.show(this.errorMessage);
        Sentry.captureException(error);
        return false;
      } finally {
        this.isSaving = false;
      }
    },
  },
};
</script>

<template>
  <span
    class="gl-flex gl-items-center gl-gap-2"
    :class="{
      'gl-group': hasEditButton && !isEditing,
      'gl-cursor-pointer': startsOnCellClick && !isEditing,
    }"
    @click="handleClick"
  >
    <slot name="prefix"></slot>

    <template v-if="!isEditing">
      <slot name="display"></slot>
      <gl-button
        v-if="hasEditButton"
        ref="editButton"
        icon="pencil"
        category="tertiary"
        size="small"
        :aria-label="editLabel"
        class="gl-ml-auto gl-shrink-0 gl-opacity-0 gl-transition-opacity focus:gl-opacity-10 group-hover:gl-opacity-10"
        data-testid="cell-edit-button"
        @click.stop="startEditing"
      />
    </template>

    <template v-else>
      <slot name="editor" v-bind="{ save, cancel: stopEditing, isSaving }"></slot>
      <gl-loading-icon v-if="isSaving" size="sm" inline class="gl-shrink-0" />
      <span v-if="isSaving && savingText" class="gl-sr-only" aria-live="polite">
        {{ savingText }}
      </span>
    </template>
  </span>
</template>
