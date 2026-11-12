<script>
import { GlBadge, GlIcon, GlTableLite, GlTooltipDirective } from '@gitlab/ui';
import { __, s__ } from '~/locale';
import HelpIcon from '~/vue_shared/components/help_icon/help_icon.vue';
import Markdown from '~/vue_shared/components/markdown/non_gfm_markdown.vue';
import DynamicValueRenderer from './value_column/dynamic_value_renderer.vue';

export default {
  name: 'PipelineInputsTable',
  ARRAY_TYPE: 'ARRAY',
  components: {
    DynamicValueRenderer,
    GlBadge,
    GlIcon,
    GlTableLite,
    HelpIcon,
    Markdown,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  i18n: {
    orphanedInputTooltip: s__(
      'Pipelines|This input is no longer defined in the configuration. Clear it from the selected inputs to remove it from the schedule.',
    ),
  },
  fields: [
    {
      key: 'name',
      label: __('Name'),
    },
    {
      key: 'description',
      label: __('Description'),
      tdAttr: { 'data-testid': 'input-description-cell' },
    },
    {
      key: 'type',
      label: __('Type'),
    },
    {
      key: 'value',
      label: __('Value'),
      tdClass: '@md/panel:gl-max-w-26',
    },
  ],
  props: {
    inputs: {
      type: Array,
      required: true,
    },
  },
  emits: ['update'],
  computed: {
    filteredItems() {
      return this.inputs.filter((input) => input.isSelected);
    },
  },
  methods: {
    handleValueUpdated({ item, value }) {
      const updatedInput = { ...item, value };
      this.$emit('update', updatedInput);
    },
    hasDescription(description) {
      return description?.length;
    },
    isArrayType(item) {
      return item.type === this.$options.ARRAY_TYPE && !item.options?.length;
    },
  },
};
</script>

<template>
  <!-- Will replace with pagination in the future. -->
  <div class="gl-overflow-y-auto @md/panel:gl-max-h-[50rem]">
    <gl-table-lite
      class="gl-mb-0"
      :items="filteredItems"
      :fields="$options.fields"
      :tbody-tr-attr="{ 'data-testid': 'input-row' }"
      stacked="sm"
    >
      <template #cell(name)="{ item }">
        <span>
          {{ item.name }}
          <span v-if="item.required" class="gl-text-danger" data-testid="required-asterisk">*</span>
          <gl-badge
            v-if="item.isOrphaned"
            v-gl-tooltip.hover
            :title="$options.i18n.orphanedInputTooltip"
            variant="warning"
            icon="status-alert"
            icon-size="sm"
            data-testid="orphaned-input-badge"
          >
            {{ s__('Pipelines|Not defined') }}
            <span class="gl-sr-only gl-select-none" data-testid="orphaned-input-description">{{
              $options.i18n.orphanedInputTooltip
            }}</span>
          </gl-badge>
        </span>
      </template>
      <template #cell(description)="{ item }">
        <markdown v-if="hasDescription(item.description)" :markdown="item.description" />
        <gl-icon v-else name="dash" :size="12" />
      </template>
      <template #cell(type)="{ item }">
        <span
          >{{ item.type.toLowerCase() }}
          <help-icon
            v-if="isArrayType(item)"
            v-gl-tooltip.hover
            :title="s__('Pipelines|Array values must be in JSON format.')"
          />
        </span>
      </template>
      <template #cell(value)="{ item }">
        <dynamic-value-renderer
          :key="`${item.name}-${item.isSelected}`"
          :item="item"
          @update="handleValueUpdated"
        />
      </template>
    </gl-table-lite>
  </div>
</template>
