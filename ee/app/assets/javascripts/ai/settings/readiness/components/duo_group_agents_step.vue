<script>
import { GlButton, GlLink, GlSprintf, GlToggle } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { s__ } from '~/locale';
import CascadingLockIcon from '~/namespaces/cascading_settings/components/cascading_lock_icon.vue';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';
import { isAgentSelected, isLocked, lockIconProps, stepStatus } from '../group_readiness';
import DuoGroupAgentPicker from './duo_group_agent_picker.vue';

export default {
  name: 'DuoGroupAgentsStep',
  components: {
    GlButton,
    GlLink,
    GlSprintf,
    GlToggle,
    CascadingLockIcon,
    DuoReadinessRow,
    DuoGroupAgentPicker,
  },
  inject: {
    isSaaS: { default: false },
    showFoundationalAgentsAvailability: { default: false },
    foundationalAgentsOwnerEnabled: { default: false },
    duoAgentPlatformOwnerSettingsPath: { default: null },
    rootAncestorName: { default: '' },
    duoCustomAgentsCascadingSettings: { default: null },
    duoExternalAgentsCascadingSettings: { default: null },
  },
  props: {
    foundationalAgentsEnabled: {
      type: Boolean,
      required: true,
    },
    foundationalAgentsStatuses: {
      type: Array,
      required: false,
      default: () => [],
    },
    customAgentsEnabled: {
      type: Boolean,
      required: true,
    },
    externalAgentsEnabled: {
      type: Boolean,
      required: true,
    },
  },
  emits: [
    'change-foundational-agents-enabled',
    'change-foundational-agents-statuses',
    'change-custom-agents-enabled',
    'change-external-agents-enabled',
  ],
  data() {
    return {
      noteId: uniqueId('duo-group-agents-note-'),
    };
  },
  computed: {
    agentsOn() {
      return this.showFoundationalAgentsAvailability
        ? this.foundationalAgentsEnabled
        : this.foundationalAgentsOwnerEnabled;
    },
    nestedDisabled() {
      return !this.agentsOn;
    },
    nestedDescribedBy() {
      return this.showAgentsNote ? this.noteId : undefined;
    },
    customAgentsLocked() {
      return isLocked(this.duoCustomAgentsCascadingSettings);
    },
    externalAgentsLocked() {
      return isLocked(this.duoExternalAgentsCascadingSettings);
    },
    ownerSettingsLinkText() {
      return this.isSaaS
        ? s__('DuoAgentPlatform|Group settings')
        : s__('DuoAgentPlatform|Admin settings');
    },
    selectedAgents() {
      return this.foundationalAgentsStatuses.filter(isAgentSelected);
    },
    // Only the top-level group picks agents; a subgroup shows the agents it picked.
    showAgentPicker() {
      return this.showFoundationalAgentsAvailability && this.foundationalAgentsStatuses.length > 0;
    },
    // On a self-managed instance the administrator decides which agents run, so there is no row.
    showInheritedAgentsRow() {
      return !this.showFoundationalAgentsAvailability && this.isSaaS;
    },
    inheritedAgents() {
      return this.showInheritedAgentsRow ? this.selectedAgents : [];
    },
    // Only a group that owns the switch can act on the note; elsewhere the owner link
    // and the namespace notice say who controls it.
    showAgentsNote() {
      return this.showFoundationalAgentsAvailability && !this.agentsOn;
    },
    inheritedAgentsDescription() {
      return this.inheritedAgents.length
        ? this.$options.i18n.foundationalAgentsInheritedDescription
        : this.$options.i18n.noInheritedAgents;
    },
  },
  methods: {
    lockIconProps,
    stepStatus,
  },
  i18n: {
    agentsTitle: s__('AiPowered|Agents'),
    foundationalAgentsTitle: s__('FoundationalAgents|Foundational agents'),
    foundationalAgentsDescription: s__(
      'DuoAgentPlatform|Projects in this group can use agents built and maintained by GitLab.',
    ),
    foundationalAgentsInheritedDescription: s__(
      'DuoAgentPlatform|Projects in this group can use these agents built and maintained by GitLab. Set by %{group}.',
    ),
    noInheritedAgents: s__('DuoAgentPlatform|No foundational agents are turned on by %{group}.'),
    customAgentsTitle: s__('DuoAgentPlatform|Custom agents'),
    externalAgentsTitle: s__('DuoAgentPlatform|External agents'),
  },
};
</script>

<template>
  <div>
    <duo-readiness-row
      :title="$options.i18n.agentsTitle"
      :description="
        s__(
          'DuoAgentPlatform|Projects in this group can use agents for tasks and complex questions.',
        )
      "
      :status="stepStatus(agentsOn)"
      data-testid="agents-row"
    >
      <template v-if="showAgentsNote" #note>
        <span :id="noteId">{{
          s__('DuoAgentPlatform|Turn on Agents to change the settings below.')
        }}</span>
      </template>
      <gl-toggle
        v-if="showFoundationalAgentsAvailability"
        :value="foundationalAgentsEnabled"
        :label="$options.i18n.agentsTitle"
        label-position="hidden"
        data-testid="agents-toggle"
        @change="$emit('change-foundational-agents-enabled', $event)"
      />
      <gl-button
        v-else-if="duoAgentPlatformOwnerSettingsPath"
        :category="agentsOn ? 'tertiary' : 'secondary'"
        size="small"
        icon="external-link"
        :href="duoAgentPlatformOwnerSettingsPath"
        data-testid="agents-owner-link"
      >
        {{ ownerSettingsLinkText }}
      </gl-button>
    </duo-readiness-row>

    <duo-readiness-row
      v-if="showAgentPicker"
      nested
      :disabled="nestedDisabled"
      :title="$options.i18n.foundationalAgentsTitle"
      :description="$options.i18n.foundationalAgentsDescription"
      :status="stepStatus(agentsOn && selectedAgents.length > 0)"
      data-testid="foundational-agents-row"
    />
    <!-- The top-level group made this choice, so the row reports it: no status icon, and it
         does not grey out with Agents. -->
    <duo-readiness-row
      v-else-if="showInheritedAgentsRow"
      nested
      :title="$options.i18n.foundationalAgentsTitle"
      data-testid="foundational-agents-row"
    >
      <template #description>
        <gl-sprintf :message="inheritedAgentsDescription">
          <template #group>
            <gl-link
              v-if="duoAgentPlatformOwnerSettingsPath"
              :href="duoAgentPlatformOwnerSettingsPath"
              data-testid="foundational-agents-owner-link"
              >{{ rootAncestorName }}</gl-link
            >
            <template v-else>{{ rootAncestorName }}</template>
          </template>
        </gl-sprintf>
      </template>
    </duo-readiness-row>

    <div
      v-if="showAgentPicker"
      class="gl-border-t gl-bg-subtle gl-py-3 gl-pl-9 gl-pr-4"
      data-testid="foundational-agent-picker-row"
    >
      <duo-group-agent-picker
        :statuses="foundationalAgentsStatuses"
        :disabled="nestedDisabled"
        :described-by="nestedDescribedBy"
        @change="$emit('change-foundational-agents-statuses', $event)"
      />
    </div>
    <div
      v-else-if="inheritedAgents.length"
      class="gl-border-t gl-bg-subtle gl-py-3 gl-pl-9 gl-pr-4"
      data-testid="foundational-agent-list-row"
    >
      <ul class="gl-m-0 gl-list-none gl-p-0 gl-text-sm">
        <li v-for="agent in inheritedAgents" :key="agent.reference" class="gl-py-1">
          {{ agent.name }}
        </li>
      </ul>
    </div>

    <duo-readiness-row
      nested
      :disabled="nestedDisabled"
      :title="$options.i18n.customAgentsTitle"
      :description="
        s__(
          'DuoAgentPlatform|Users with the Maintainer or Owner role for a project can create new agents.',
        )
      "
      :status="stepStatus(customAgentsEnabled)"
      data-testid="custom-agents-row"
    >
      <template v-if="customAgentsLocked" #title-icon>
        <cascading-lock-icon
          v-bind="lockIconProps(duoCustomAgentsCascadingSettings)"
          class="gl-ml-1"
        />
      </template>
      <gl-toggle
        :value="customAgentsEnabled"
        :disabled="nestedDisabled || customAgentsLocked"
        :accessible-disabled="!customAgentsLocked"
        :aria-describedby="nestedDescribedBy"
        :label="$options.i18n.customAgentsTitle"
        label-position="hidden"
        data-testid="custom-agents-toggle"
        @change="$emit('change-custom-agents-enabled', $event)"
      />
    </duo-readiness-row>

    <duo-readiness-row
      nested
      :disabled="nestedDisabled"
      :title="$options.i18n.externalAgentsTitle"
      :description="s__('DuoAgentPlatform|Projects can use third-party agents.')"
      :status="stepStatus(externalAgentsEnabled)"
      data-testid="external-agents-row"
    >
      <template v-if="externalAgentsLocked" #title-icon>
        <cascading-lock-icon
          v-bind="lockIconProps(duoExternalAgentsCascadingSettings)"
          class="gl-ml-1"
        />
      </template>
      <gl-toggle
        :value="externalAgentsEnabled"
        :disabled="nestedDisabled || externalAgentsLocked"
        :accessible-disabled="!externalAgentsLocked"
        :aria-describedby="nestedDescribedBy"
        :label="$options.i18n.externalAgentsTitle"
        label-position="hidden"
        data-testid="external-agents-toggle"
        @change="$emit('change-external-agents-enabled', $event)"
      />
    </duo-readiness-row>
  </div>
</template>
