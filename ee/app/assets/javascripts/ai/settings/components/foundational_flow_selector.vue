<script>
import { GlFormCheckbox, GlFormCheckboxGroup } from '@gitlab/ui';
import SafeHtml from '~/vue_shared/directives/safe_html';

export default {
  name: 'FoundationalFlowSelector',
  components: {
    GlFormCheckbox,
    GlFormCheckboxGroup,
  },
  directives: {
    SafeHtml,
  },
  inject: ['availableFoundationalFlows'],
  props: {
    value: {
      type: Array,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    describedBy: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['input'],
};
</script>

<template>
  <gl-form-checkbox-group
    :checked="value"
    :disabled="disabled"
    :aria-label="s__('DuoAgentPlatform|Foundational flows')"
    class="gl-ml-6 gl-mt-3"
    data-testid="foundational-flow-checkbox-group"
    @input="$emit('input', $event)"
  >
    <div v-for="flow in availableFoundationalFlows" :key="flow.reference">
      <gl-form-checkbox
        :value="flow.reference"
        :aria-describedby="describedBy"
        data-testid="foundational-flow-checkbox"
      >
        <div>
          {{ flow.name }}
          <div
            v-if="flow.descriptionHtml"
            v-safe-html="flow.descriptionHtml"
            class="md gl-text-sm gl-text-subtle"
          ></div>
          <div v-else class="gl-text-sm gl-text-subtle">{{ flow.description }}</div>
        </div>
      </gl-form-checkbox>
      <slot name="after-flow" :reference="flow.reference"></slot>
    </div>
  </gl-form-checkbox-group>
</template>
