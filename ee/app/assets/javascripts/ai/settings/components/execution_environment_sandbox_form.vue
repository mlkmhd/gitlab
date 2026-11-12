<script>
import { GlFormCheckbox, GlLink, GlSprintf, GlTooltipDirective } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';

export default {
  name: 'ExecutionEnvironmentSandboxForm',
  components: {
    GlFormCheckbox,
    GlLink,
    GlSprintf,
  },
  directives: {
    tooltip: GlTooltipDirective,
  },
  requireSandboxHelpPath: helpPagePath('user/duo_agent_platform/environment_sandbox', {
    anchor: 'require-flows-to-run-in-the-sandbox',
  }),
  props: {
    requireSandbox: {
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
  <div class="gl-my-4">
    <h3 class="gl-heading-4 gl-mb-5 gl-mt-6">
      {{ s__('AiPowered|Execution environment sandbox') }}
    </h3>

    <gl-form-checkbox
      :checked="requireSandbox"
      :disabled="disabledCheckbox"
      @change="checkboxChanged"
    >
      <span
        v-tooltip="
          disabledCheckbox
            ? s__('AiPowered|This setting only applies when GitLab Duo is available.')
            : ''
        "
        >{{ s__("AiPowered|Don't run flows when the sandbox is unavailable") }}</span
      >
      <template #help>
        <gl-sprintf
          :message="
            s__(
              'AiPowered|If the sandbox is unavailable, flows that run on GitLab Runner fail instead of running without network and file system isolation. %{linkStart}Learn more about requiring the sandbox%{linkEnd}.',
            )
          "
        >
          <template #link="{ content }">
            <gl-link :href="$options.requireSandboxHelpPath" target="_blank">{{ content }}</gl-link>
          </template>
        </gl-sprintf>
      </template>
    </gl-form-checkbox>
  </div>
</template>
