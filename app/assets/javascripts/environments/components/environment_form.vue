<script>
import {
  GlButton,
  GlForm,
  GlFormGroup,
  GlFormInput,
  GlCollapsibleListbox,
  GlLink,
  GlSprintf,
} from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import { isAbsolute } from '~/lib/utils/url_utility';
import { __, s__ } from '~/locale';
import {
  ENVIRONMENT_NEW_HELP_TEXT,
  ENVIRONMENT_EDIT_HELP_TEXT,
} from 'ee_else_ce/environments/constants';
import csrf from '~/lib/utils/csrf';
import MarkdownEditor from '~/vue_shared/components/markdown/markdown_editor.vue';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import getUserAuthorizedAgents from '../graphql/queries/user_authorized_agents.query.graphql';
import EnvironmentFluxResourceSelector from './environment_flux_resource_selector.vue';
import EnvironmentNamespaceSelector from './environment_namespace_selector.vue';

export default {
  name: 'EnvironmentForm',
  components: {
    GlButton,
    GlForm,
    GlFormGroup,
    GlFormInput,
    GlCollapsibleListbox,
    GlLink,
    GlSprintf,
    EnvironmentFluxResourceSelector,
    EnvironmentNamespaceSelector,
    MarkdownEditor,
  },
  inject: {
    protectedEnvironmentSettingsPath: { default: '' },
    projectPath: { default: '' },
    kasTunnelUrl: { default: '' },
    markdownPreviewPath: { default: '' },
  },
  props: {
    environment: {
      required: true,
      type: Object,
    },
    title: {
      required: true,
      type: String,
    },
    cancelPath: {
      required: true,
      type: String,
    },
    loading: {
      required: false,
      type: Boolean,
      default: false,
    },
  },
  emits: ['change', 'submit'],
  i18n: {
    helpNewMessage: ENVIRONMENT_NEW_HELP_TEXT,
    helpEditMessage: ENVIRONMENT_EDIT_HELP_TEXT,
    descriptionLabel: __('Description'),
    agentHelpText: s__('Environments|Select agent'),
  },
  agentSelectorHelpPagePath: helpPagePath('user/clusters/agent/user_access.md'),
  environmentsHelpPagePath: helpPagePath('ci/environments/_index.md'),
  renamingDisabledHelpPagePath: helpPagePath('ci/environments/_index.md', {
    anchor: 'rename-an-environment',
  }),
  markdownDocsPath: helpPagePath('user/markdown'),
  restrictedToolbarItems: ['full-screen'],
  data() {
    return {
      visited: {
        name: null,
        url: null,
      },
      userAccessAuthorizedAgents: [],
      loadingAgentsList: false,
      selectedAgentId: this.environment.clusterAgentId,
      agentSearchTerm: '',
      selectedNamespace: this.environment.kubernetesNamespace,
    };
  },
  computed: {
    isNameDisabled() {
      return Boolean(this.environment.id);
    },
    showEditHelp() {
      return this.isNameDisabled && Boolean(this.protectedEnvironmentSettingsPath);
    },
    valid() {
      return {
        name: this.visited.name && this.environment.name !== '',
        url: this.visited.url && isAbsolute(this.environment.externalUrl),
      };
    },
    agentsList() {
      return this.userAccessAuthorizedAgents.map((node) => {
        return {
          value: node?.agent?.id,
          text: node?.agent?.name,
        };
      });
    },
    agentDropdownToggleText() {
      if (!this.selectedAgentId) {
        return this.$options.i18n.agentHelpText;
      }
      const selectedAgentById = this.agentsList.find(
        (agent) => agent.value === this.selectedAgentId,
      );
      return selectedAgentById?.text || this.environment.clusterAgent?.name;
    },
    filteredAgentsList() {
      const lowerCasedSearchTerm = this.agentSearchTerm.toLowerCase();
      return this.agentsList.filter((item) =>
        item.text.toLowerCase().includes(lowerCasedSearchTerm),
      );
    },
    showNamespaceAndResourceSelectors() {
      return Boolean(this.selectedAgentId);
    },
    k8sAccessConfiguration() {
      if (!this.showNamespaceAndResourceSelectors) {
        return null;
      }
      return {
        basePath: this.kasTunnelUrl,
        headers: {
          'GitLab-Agent-Id': getIdFromGraphQLId(this.selectedAgentId),
          'Content-Type': 'application/json',
          Accept: 'application/json',
          ...csrf.headers,
        },
        credentials: 'include',
      };
    },
    descriptionFieldProps() {
      return {
        'aria-label': this.$options.i18n.descriptionLabel,
        placeholder: s__('Environments|Write a description or drag your files here…'),
        id: 'environment_description',
      };
    },
  },
  watch: {
    environment(change) {
      this.selectedAgentId = change.clusterAgentId;
      this.selectedNamespace = change.kubernetesNamespace;
    },
  },
  methods: {
    onChange(env) {
      this.$emit('change', env);
    },
    visit(field) {
      this.visited[field] = true;
    },
    updateDescription($event) {
      if (this.environment.description !== $event) {
        this.onChange({ ...this.environment, description: $event });
      }
    },
    getAgentsList() {
      this.$apollo.addSmartQuery('userAccessAuthorizedAgents', {
        variables() {
          return { projectFullPath: this.projectPath };
        },
        query: getUserAuthorizedAgents,
        update: (data) => {
          return data?.project?.userAccessAuthorizedAgents?.nodes || [];
        },
        watchLoading: (isLoading) => {
          this.loadingAgentsList = isLoading;
        },
      });
    },
    onAgentSearch(search) {
      this.agentSearchTerm = search;
    },
    onAgentChange($event) {
      this.selectedNamespace = null;
      this.onChange({
        ...this.environment,
        clusterAgentId: $event,
        kubernetesNamespace: null,
        fluxResourcePath: null,
      });
    },
  },
};
</script>
<template>
  <div>
    <h1 class="page-title gl-text-size-h-display">
      {{ title }}
    </h1>
    <div class="row gl-col-12">
      <h4 class="gl-mt-0">
        {{ __('Environments') }}
      </h4>
      <p class="gl-w-full">
        <gl-sprintf
          :message="showEditHelp ? $options.i18n.helpEditMessage : $options.i18n.helpNewMessage"
        >
          <template #link="{ content }">
            <gl-link
              :href="
                showEditHelp ? protectedEnvironmentSettingsPath : $options.environmentsHelpPagePath
              "
              >{{ content }}</gl-link
            >
          </template>
        </gl-sprintf>
      </p>
      <gl-form
        id="new_environment"
        :aria-label="title"
        class="gl-w-full"
        @submit.prevent="$emit('submit')"
      >
        <gl-form-group
          :label="__('Name')"
          label-for="environment_name"
          :state="valid.name"
          :invalid-feedback="__('This field is required')"
        >
          <template v-if="isNameDisabled" #description>
            {{ __("You cannot rename an environment after it's created.") }}
            <gl-link :href="$options.renamingDisabledHelpPagePath" target="_blank">
              {{ __('How do I rename an environment?') }}
            </gl-link>
          </template>
          <gl-form-input
            id="environment_name"
            :value="environment.name"
            :state="valid.name"
            :disabled="isNameDisabled"
            name="environment[name]"
            required
            @input="onChange({ ...environment, name: $event })"
            @blur="visit('name')"
          />
        </gl-form-group>
        <gl-form-group
          :label="$options.i18n.descriptionLabel"
          :description="
            s__('Environments|The description is displayed to anyone who can see this environment.')
          "
          label-for="environment_description"
          :state="valid.description"
        >
          <div class="common-note-form gfm-form">
            <markdown-editor
              :value="environment.description"
              :render-markdown-path="markdownPreviewPath"
              :form-field-props="descriptionFieldProps"
              :restricted-tool-bar-items="$options.restrictedToolbarItems"
              :markdown-docs-path="$options.markdownDocsPath"
              :disabled="loading"
              @input="updateDescription"
            />
          </div>
        </gl-form-group>
        <gl-form-group
          :label="__('External URL')"
          :state="valid.url"
          :invalid-feedback="__('The URL should start with http:// or https://')"
          label-for="environment_external_url"
        >
          <gl-form-input
            id="environment_external_url"
            :value="environment.externalUrl"
            :state="valid.url"
            name="environment[external_url]"
            type="url"
            @input="onChange({ ...environment, externalUrl: $event })"
            @blur="visit('url')"
          />
        </gl-form-group>

        <gl-form-group :label="s__('Environments|GitLab agent')" label-for="environment_agent">
          <gl-collapsible-listbox
            id="environment_agent"
            v-model="selectedAgentId"
            class="gl-w-full"
            data-testid="agent-selector"
            block
            :items="filteredAgentsList"
            :loading="loadingAgentsList"
            :toggle-text="agentDropdownToggleText"
            :header-text="$options.i18n.agentHelpText"
            :reset-button-label="__('Reset')"
            :searchable="true"
            @shown="getAgentsList"
            @search="onAgentSearch"
            @select="onAgentChange"
            @reset="onChange({ ...environment, clusterAgentId: null })"
          />
          <template #description>
            {{
              s__('Environments|Select an agent with Kubernetes access to the project or group.')
            }}
            <gl-link :href="$options.agentSelectorHelpPagePath" target="_blank"
              >{{ s__('Environments|How do I grant Kubernetes access?') }}
            </gl-link>
          </template>
        </gl-form-group>

        <template v-if="showNamespaceAndResourceSelectors">
          <environment-namespace-selector
            :namespace="selectedNamespace"
            :configuration="k8sAccessConfiguration"
            @change="
              onChange({ ...environment, kubernetesNamespace: $event, fluxResourcePath: null })
            "
          />

          <environment-flux-resource-selector
            :namespace="selectedNamespace"
            :configuration="k8sAccessConfiguration"
            :flux-resource-path="environment.fluxResourcePath"
            @change="onChange({ ...environment, fluxResourcePath: $event })"
          />
        </template>

        <div class="gl-flex gl-gap-3">
          <gl-button
            :loading="loading"
            type="submit"
            variant="confirm"
            name="commit"
            class="js-no-auto-disable"
            data-testid="save-environment"
            >{{ __('Save') }}</gl-button
          >
          <gl-button :href="cancelPath">{{ __('Cancel') }}</gl-button>
        </div>
      </gl-form>
    </div>
  </div>
</template>
