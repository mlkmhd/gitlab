<script>
import { GlAlert, GlLink } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import { s__, sprintf } from '~/locale';

// The unnamed variants cover commands that request an agent by ID only
const MESSAGES = {
  instance: {
    named: s__(
      "DuoAgenticChat|The %{agentName} agent isn't available on this instance. Contact your administrator.",
    ),
    unnamed: s__(
      "DuoAgenticChat|The requested agent isn't available on this instance. Contact your administrator.",
    ),
  },
  namespaceContext: {
    named: s__("DuoAgenticChat|The %{agentName} agent isn't available in this group or project."),
    unnamed: s__("DuoAgenticChat|The requested agent isn't available in this group or project."),
  },
  defaultNamespace: {
    named: s__(
      "DuoAgenticChat|The %{agentName} agent isn't available for your default GitLab Duo namespace.",
    ),
    unnamed: s__(
      "DuoAgenticChat|The requested agent isn't available for your default GitLab Duo namespace.",
    ),
  },
};

export default {
  name: 'AgentUnavailableAlert',
  components: {
    GlAlert,
    GlLink,
  },
  props: {
    agentName: {
      type: String,
      required: false,
      default: '',
    },
    defaultNamespaceGoverns: {
      type: Boolean,
      required: false,
      default: false,
    },
    // Outside GitLab.com, instance settings decide agent availability
    isSaas: {
      type: Boolean,
      required: false,
      default: false,
    },
    preferencesPath: {
      type: String,
      required: false,
      default: '',
    },
  },
  computed: {
    showPreferencesLink() {
      return this.isSaas && this.defaultNamespaceGoverns && Boolean(this.preferencesPath);
    },
    messages() {
      if (!this.isSaas) {
        return MESSAGES.instance;
      }

      if (this.defaultNamespaceGoverns) {
        return MESSAGES.defaultNamespace;
      }

      return MESSAGES.namespaceContext;
    },
    message() {
      if (!this.agentName) {
        return this.messages.unnamed;
      }

      return sprintf(this.messages.named, { agentName: this.agentName }, false);
    },
  },
  fallbackMessage: s__('DuoAgenticChat|Messages in this chat go to the GitLab Duo agent.'),
  foundationalAgentsHelpPath: helpPagePath(
    'user/duo_agent_platform/agents/foundational_agents/_index',
    { anchor: 'turn-foundational-agents-on-or-off' },
  ),
};
</script>

<template>
  <gl-alert variant="warning" :dismissible="false" data-testid="agent-unavailable-alert">
    <p class="gl-mb-2">{{ message }} {{ $options.fallbackMessage }}</p>
    <gl-link
      v-if="showPreferencesLink"
      :href="preferencesPath"
      data-testid="agent-unavailable-preferences-link"
    >
      {{ s__('DuoAgenticChat|Switch namespace') }}
    </gl-link>
    <gl-link
      v-else
      :href="$options.foundationalAgentsHelpPath"
      target="_blank"
      data-testid="agent-unavailable-help-link"
    >
      {{ s__('DuoAgenticChat|Learn more') }}
    </gl-link>
  </gl-alert>
</template>
