<script>
import { GlFormCheckbox, GlFormCheckboxGroup } from '@gitlab/ui';
import { isAgentSelected } from '../group_readiness';

export default {
  name: 'DuoGroupAgentPicker',
  components: {
    GlFormCheckbox,
    GlFormCheckboxGroup,
  },
  props: {
    statuses: {
      type: Array,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    // id of the note that says why the checkboxes are disabled.
    describedBy: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['change'],
  computed: {
    selectedReferences() {
      return this.statuses.filter(isAgentSelected).map((agent) => agent.reference);
    },
    allSelected() {
      return this.statuses.length > 0 && this.selectedReferences.length === this.statuses.length;
    },
    someSelected() {
      return this.selectedReferences.length > 0 && !this.allSelected;
    },
  },
  methods: {
    onSelectionChange(references) {
      this.$emit(
        'change',
        this.statuses.map((agent) => ({ ...agent, enabled: references.includes(agent.reference) })),
      );
    },
    toggleAll(checked) {
      this.$emit(
        'change',
        this.statuses.map((agent) => ({ ...agent, enabled: checked })),
      );
    },
  },
};
</script>
<template>
  <div>
    <gl-form-checkbox
      :checked="allSelected"
      :indeterminate="someSelected"
      :disabled="disabled"
      :aria-describedby="describedBy"
      class="gl-ml-6 gl-mt-3"
      data-testid="foundational-agent-select-all"
      @change="toggleAll"
    >
      {{ s__('DuoAgentPlatform|Select all agents') }}
    </gl-form-checkbox>
    <gl-form-checkbox-group
      :checked="selectedReferences"
      :disabled="disabled"
      :aria-label="s__('FoundationalAgents|Foundational agents')"
      class="gl-ml-6 gl-mt-3 gl-pl-5"
      data-testid="foundational-agent-checkbox-group"
      @change="onSelectionChange"
    >
      <gl-form-checkbox
        v-for="agent in statuses"
        :key="agent.reference"
        :value="agent.reference"
        :aria-describedby="describedBy"
        data-testid="foundational-agent-checkbox"
      >
        <div>
          {{ agent.name }}
          <div class="gl-text-sm gl-text-subtle">{{ agent.description }}</div>
        </div>
      </gl-form-checkbox>
    </gl-form-checkbox-group>
  </div>
</template>
