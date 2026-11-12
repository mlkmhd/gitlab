<script>
import {
  GlAlert,
  GlCollapsibleListbox,
  GlFormGroup,
  GlFormInput,
  GlFormRadioGroup,
  GlModal,
  GlSprintf,
} from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { __, s__ } from '~/locale';
import { STATUS_CATEGORIES, STATUS_CATEGORIES_MAP } from 'ee/work_items/constants';

const CATEGORY_ORDER = Object.keys(STATUS_CATEGORIES_MAP);

// Mirrors the length validation of WorkItems::Statuses::Custom::Status.
const NAME_MAX_LENGTH = 32;

export default {
  name: 'CreateStatusModal',
  components: {
    GlAlert,
    GlCollapsibleListbox,
    GlFormGroup,
    GlFormInput,
    GlFormRadioGroup,
    GlModal,
    GlSprintf,
  },
  props: {
    visible: {
      type: Boolean,
      required: true,
    },
    groupName: {
      type: String,
      required: true,
    },
    initialName: {
      type: String,
      required: false,
      default: '',
    },
    initialCategory: {
      type: String,
      required: false,
      default: STATUS_CATEGORIES.IN_PROGRESS,
      validator: (value) => Object.hasOwn(STATUS_CATEGORIES_MAP, value),
    },
    lifecycles: {
      type: Array,
      required: true,
    },
    initialLifecycleId: {
      type: String,
      required: false,
      default: null,
    },
    existingNames: {
      type: Array,
      required: false,
      default: () => [],
    },
    usesDefaultStatuses: {
      type: Boolean,
      required: false,
      default: false,
    },
    isSaving: {
      type: Boolean,
      required: false,
      default: false,
    },
    error: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['submit', 'hide'],
  data() {
    return {
      name: this.initialName,
      category: this.initialCategory,
      lifecycleId: this.initialLifecycleId,
      modalId: uniqueId('dap-factory-create-status-'),
      nameId: uniqueId('dap-factory-status-name-'),
      lifecycleFieldId: uniqueId('dap-factory-status-lifecycle-'),
    };
  },
  computed: {
    // The lifecycles can still be loading when the modal opens, so fall back as they arrive.
    selectedLifecycleId() {
      return this.lifecycleId ?? this.lifecycles[0]?.id ?? null;
    },
    trimmedName() {
      return this.name.trim();
    },
    isDuplicate() {
      const name = this.trimmedName.toLowerCase();

      return this.existingNames.some((existing) => existing.toLowerCase() === name);
    },
    nameError() {
      return this.isDuplicate
        ? s__('DapSoftwareFactory|A status with this name already exists.')
        : '';
    },
    nameState() {
      return this.nameError ? false : null;
    },
    canSubmit() {
      return Boolean(this.trimmedName) && !this.isDuplicate && Boolean(this.selectedLifecycleId);
    },
    categoryOptions() {
      return CATEGORY_ORDER.map((value) => ({ value, text: STATUS_CATEGORIES_MAP[value].label }));
    },
    lifecycleItems() {
      return this.lifecycles.map(({ id, name }) => ({ value: id, text: name }));
    },
    selectedLifecycleText() {
      return (
        this.lifecycleItems.find(({ value }) => value === this.selectedLifecycleId)?.text ?? ''
      );
    },
    actionPrimary() {
      return {
        text: s__('DapSoftwareFactory|Create status'),
        attributes: { variant: 'confirm', disabled: !this.canSubmit, loading: this.isSaving },
      };
    },
    actionCancel() {
      return { text: __('Cancel'), attributes: { disabled: this.isSaving } };
    },
  },
  methods: {
    reset() {
      this.name = this.initialName;
      this.category = this.initialCategory;
      this.lifecycleId = this.initialLifecycleId;
    },
    // GlModal renders its own header close button, so hide-header-close does
    // not reach it. Guarding the hide event covers that button, the cancel
    // button, escape and the backdrop in one place.
    onHide(event) {
      if (this.isSaving) {
        event.preventDefault();
        return;
      }

      this.$emit('hide');
    },
    // The modal stays open while the status is saved, so that a server error lands next to the form.
    onPrimary(event) {
      event.preventDefault();

      if (!this.canSubmit || this.isSaving) return;

      this.$emit('submit', {
        name: this.trimmedName,
        category: this.category,
        color: STATUS_CATEGORIES_MAP[this.category].color,
        lifecycleId: this.selectedLifecycleId,
      });
    },
  },
  NAME_MAX_LENGTH,
};
</script>

<template>
  <gl-modal
    :visible="visible"
    :modal-id="modalId"
    :title="s__('DapSoftwareFactory|Create status')"
    :action-primary="actionPrimary"
    :action-cancel="actionCancel"
    data-testid="create-status-modal"
    @show="reset"
    @primary="onPrimary"
    @hide="onHide"
  >
    <gl-alert
      v-if="error"
      variant="danger"
      :dismissible="false"
      class="gl-mb-5"
      data-testid="create-status-error"
    >
      {{ error }}
    </gl-alert>

    <gl-alert variant="info" :dismissible="false" class="gl-mb-5" data-testid="create-status-scope">
      <gl-sprintf
        :message="
          s__(
            'DapSoftwareFactory|The status is added to %{group} straight away, for every project in it. It does not wait for you to save the configuration.',
          )
        "
      >
        <template #group>
          <strong>{{ groupName }}</strong>
        </template>
      </gl-sprintf>
      <template v-if="usesDefaultStatuses">
        {{
          s__(
            'DapSoftwareFactory|This group uses the default statuses, so this also switches it to custom statuses.',
          )
        }}
      </template>
    </gl-alert>

    <gl-form-group
      :label="s__('DapSoftwareFactory|Name')"
      :label-for="nameId"
      :invalid-feedback="nameError"
      :state="nameState"
    >
      <gl-form-input
        :id="nameId"
        v-model="name"
        :state="nameState"
        :maxlength="$options.NAME_MAX_LENGTH"
        :disabled="isSaving"
        data-testid="create-status-name"
      />
    </gl-form-group>

    <gl-form-group :label="s__('DapSoftwareFactory|Category')">
      <gl-form-radio-group
        v-model="category"
        :options="categoryOptions"
        :disabled="isSaving"
        data-testid="create-status-category"
      />
    </gl-form-group>

    <gl-form-group
      v-if="lifecycles.length > 1"
      :label="s__('DapSoftwareFactory|Lifecycle')"
      :label-for="lifecycleFieldId"
      :description="
        s__(
          'DapSoftwareFactory|A trigger only fires for work items whose type uses this lifecycle.',
        )
      "
      class="gl-mb-0"
    >
      <gl-collapsible-listbox
        :selected="selectedLifecycleId"
        :toggle-id="lifecycleFieldId"
        :items="lifecycleItems"
        :toggle-text="selectedLifecycleText"
        :disabled="isSaving"
        block
        data-testid="create-status-lifecycle"
        @select="lifecycleId = $event"
      />
    </gl-form-group>
  </gl-modal>
</template>
