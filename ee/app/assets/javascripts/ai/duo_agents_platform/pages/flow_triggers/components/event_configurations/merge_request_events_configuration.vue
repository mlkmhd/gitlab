<script>
import { GlCollapsibleListbox, GlFormGroup } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { s__ } from '~/locale';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import {
  FILTER_FIELD_ACTION,
  FILTER_FIELD_MERGE_REQUEST_CREATED_BY_FLOW,
  FILTER_FIELD_MERGE_REQUEST_DRAFT,
  FLOW_TRIGGER_TYPE_MERGE_REQUEST,
  MERGE_REQUEST_ACTION_READY,
  MERGE_REQUEST_ACTIONS,
  MERGE_REQUEST_CREATED_BY_FLOW_OPTIONS,
  MERGE_REQUEST_DRAFT_OPTIONS,
} from 'ee/ai/duo_agents_platform/constants';
import {
  parseMergeRequestActionFilter,
  parseMergeRequestFieldFilter,
  withFilterRule,
} from 'ee/ai/duo_agents_platform/utils';
import EventActionsConfiguration from './event_actions_configuration.vue';

const SCOPE = FLOW_TRIGGER_TYPE_MERGE_REQUEST.value;

export default {
  name: 'MergeRequestEventsConfiguration',
  components: {
    EventActionsConfiguration,
    GlCollapsibleListbox,
    GlFormGroup,
  },
  mixins: [glFeatureFlagsMixin()],
  props: {
    value: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    invalidFeedback: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['input'],
  data() {
    return {
      createdByFlowToggleId: uniqueId('merge-request-created-by-flow-toggle-'),
      draftToggleId: uniqueId('merge-request-draft-toggle-'),
    };
  },
  computed: {
    showFieldListboxes() {
      return Boolean(this.glFeatures.dapSoftwareFactory);
    },
    isReadySelected() {
      return parseMergeRequestActionFilter(this.value).includes(MERGE_REQUEST_ACTION_READY.value);
    },
    fieldListboxes() {
      return [
        {
          field: FILTER_FIELD_MERGE_REQUEST_CREATED_BY_FLOW,
          testId: 'created-by-flow',
          toggleId: this.createdByFlowToggleId,
          label: s__('DuoAgentsPlatform|Created by'),
          emptyText: s__('DuoAgentsPlatform|Anyone'),
          headerText: s__('DuoAgentsPlatform|Select creator'),
          description: s__(
            'DuoAgentsPlatform|Run only for merge requests that a flow created, or only for other merge requests. Leave empty to run for any merge request.',
          ),
          options: MERGE_REQUEST_CREATED_BY_FLOW_OPTIONS,
          disabledRuleValues: [],
        },
        {
          field: FILTER_FIELD_MERGE_REQUEST_DRAFT,
          testId: 'draft',
          toggleId: this.draftToggleId,
          label: s__('DuoAgentsPlatform|Draft'),
          emptyText: s__('DuoAgentsPlatform|Draft or ready'),
          headerText: s__('DuoAgentsPlatform|Select draft status'),
          description: this.isReadySelected
            ? s__('DuoAgentsPlatform|Draft merge requests are not available with Marked ready.')
            : s__(
                'DuoAgentsPlatform|Run only for draft merge requests, or only for merge requests that are not drafts. Leave empty to run for both.',
              ),
          options: MERGE_REQUEST_DRAFT_OPTIONS,
          disabledRuleValues: this.isReadySelected ? [true] : [],
        },
      ].map((listbox) => {
        const ruleValue = parseMergeRequestFieldFilter(this.value, listbox.field);
        const selectedOption = listbox.options.find((option) => option.ruleValue === ruleValue);

        return {
          ...listbox,
          // A stored value stays selected, also when it is disabled, so the user can clear it.
          items: listbox.options.map(({ value, text, ruleValue: optionRuleValue }) => ({
            value,
            text,
            disabled: listbox.disabledRuleValues.includes(optionRuleValue),
          })),
          selected: selectedOption?.value ?? null,
          toggleText: selectedOption?.text ?? listbox.emptyText,
        };
      });
    },
  },
  methods: {
    onFieldSelect({ field, options }, selectedValue) {
      const ruleValue = options.find(({ value }) => value === selectedValue)?.ruleValue;

      this.$emit(
        'input',
        withFilterRule({
          filter: this.value,
          scope: SCOPE,
          field,
          values: ruleValue === undefined ? [] : [ruleValue],
        }),
      );
    },
  },
  MERGE_REQUEST_ACTIONS,
  FILTER_FIELD_ACTION,
  SCOPE,
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-4">
    <event-actions-configuration
      :scope="$options.SCOPE"
      :field="$options.FILTER_FIELD_ACTION"
      :actions="$options.MERGE_REQUEST_ACTIONS"
      :listbox-header-text="s__('DuoAgentsPlatform|Select merge request actions')"
      :value="value"
      :invalid-feedback="invalidFeedback"
      @input="$emit('input', $event)"
    />

    <template v-if="showFieldListboxes">
      <gl-form-group
        v-for="listbox in fieldListboxes"
        :key="listbox.field"
        :label="listbox.label"
        :label-for="listbox.toggleId"
        :description="listbox.description"
        class="!gl-mb-0"
        :data-testid="`${listbox.testId}-form-group`"
      >
        <gl-collapsible-listbox
          :toggle-id="listbox.toggleId"
          :items="listbox.items"
          :selected="listbox.selected"
          :toggle-text="listbox.toggleText"
          :header-text="listbox.headerText"
          :reset-button-label="__('Clear')"
          block
          :data-testid="`${listbox.testId}-listbox`"
          @select="onFieldSelect(listbox, $event)"
          @reset="onFieldSelect(listbox, null)"
        />
      </gl-form-group>
    </template>
  </div>
</template>
