<script>
import { GlFormCheckbox, GlFormGroup, GlTooltipDirective } from '@gitlab/ui';

export default {
  name: 'DuoWorkflowFileAttachmentsForm',
  components: {
    GlFormCheckbox,
    GlFormGroup,
  },
  directives: {
    tooltip: GlTooltipDirective,
  },
  props: {
    duoWorkflowFileAttachmentsEnabled: {
      type: Boolean,
      required: true,
    },
    disabledCheckbox: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['change'],
  methods: {
    checkboxChanged(value) {
      this.$emit('change', value);
    },
  },
};
</script>
<template>
  <gl-form-group :label="s__('DuoWorkflowSettings|File attachments')">
    <gl-form-checkbox
      :checked="duoWorkflowFileAttachmentsEnabled"
      :disabled="disabledCheckbox"
      data-testid="duo-workflow-file-attachments-enabled-checkbox"
      @change="checkboxChanged"
    >
      <span
        v-tooltip="
          disabledCheckbox
            ? s__('AiPowered|This setting only applies when GitLab Duo is available.')
            : ''
        "
        >{{ s__('DuoWorkflowSettings|Allow file attachments') }}</span
      >
      <template #help>
        {{
          s__(
            'DuoWorkflowSettings|Users can attach files to GitLab Duo Chat messages. GitLab sends attached files to the AI model.',
          )
        }}
      </template>
    </gl-form-checkbox>
  </gl-form-group>
</template>
