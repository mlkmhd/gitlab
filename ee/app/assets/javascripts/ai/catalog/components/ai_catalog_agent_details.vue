<script>
import { GlLink, GlSprintf, GlToken, GlTooltipDirective, GlTruncateText } from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__ } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import { convertToTitleCase } from '~/lib/utils/text_utility';
import glAbilitiesMixin from '~/vue_shared/mixins/gl_abilities_mixin';
import { canReadMcpServer } from '../permissions';
import { getByVersionKey } from '../utils';
import { AI_CATALOG_TYPE_THIRD_PARTY_FLOW } from '../constants';
import aiCatalogMcpToolsQuery from '../graphql/queries/ai_catalog_mcp_tools.query.graphql';
import AiCatalogItemField from './ai_catalog_item_field.vue';
import AiCatalogItemFieldServiceAccount from './ai_catalog_item_field_service_account.vue';
import FormFlowDefinition from './form_flow_definition.vue';
import TriggerField from './trigger_field.vue';
import FormSection from './form_section.vue';

export default {
  name: 'AiCatalogAgentDetails',
  components: {
    AiCatalogItemField,
    AiCatalogItemFieldServiceAccount,
    FormFlowDefinition,
    FormSection,
    GlLink,
    GlSprintf,
    GlToken,
    GlTruncateText,
    TriggerField,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [glAbilitiesMixin()],
  props: {
    item: {
      type: Object,
      required: true,
    },
    versionKey: {
      type: String,
      required: true,
    },
  },
  apollo: {
    availableMcpTools: {
      query: aiCatalogMcpToolsQuery,
      update: (data) =>
        Object.fromEntries((data.aiCatalogMcpTools?.nodes ?? []).map((t) => [t.name, t])),
      error(error) {
        Sentry.captureException(error);
      },
    },
  },
  data() {
    return {
      availableMcpTools: {},
    };
  },
  truncateTextToggleButtonProps: {
    class: 'gl-font-regular',
  },
  computed: {
    version() {
      return getByVersionKey(this.item, this.versionKey);
    },
    tools() {
      const builtInTools = (this.version.tools?.nodes ?? []).map((t) => ({
        key: `builtin-${t.id}`,
        title: t.title,
        description: t.description,
        source: 'builtin',
        iconUrl: null,
      }));
      const mcpTools = (this.version.mcpTools ?? []).map((name) => {
        const enriched = this.availableMcpTools?.[name];
        const icon = enriched?.icons?.find((i) => i.theme === 'light') || enriched?.icons?.[0];
        return {
          key: `mcp-${name}`,
          title: enriched?.title ?? convertToTitleCase(name.replace(/_/g, ' ')),
          description: enriched?.description ?? '',
          source: 'mcp',
          iconUrl: icon?.src ?? null,
        };
      });
      return [...builtInTools, ...mcpTools].sort((a, b) => a.title.localeCompare(b.title));
    },
    mcpServers() {
      return [...(this.version.mcpServers?.nodes ?? [])].sort((a, b) =>
        a.name.localeCompare(b.name),
      );
    },
    systemPrompt() {
      return this.version.systemPrompt;
    },
    definition() {
      return this.version.definition;
    },
    isThirdPartyFlow() {
      return this.item.itemType === AI_CATALOG_TYPE_THIRD_PARTY_FLOW;
    },
    typeField() {
      if (this.isThirdPartyFlow) {
        return s__('AICatalog|External');
      }
      if (this.item.foundational) {
        return s__('AICatalog|Foundational');
      }
      return s__('AICatalog|Custom');
    },
    hasProjectConfiguration() {
      return Boolean(this.item.configurationForProject);
    },
    serviceAccount() {
      if (this.hasProjectConfiguration) {
        return this.item.configurationForProject?.flowTriggers?.[0]?.user;
      }
      return this.item.configurationForGroup?.serviceAccount;
    },
    canReadMcpServers() {
      return canReadMcpServer({ glAbilities: this.glAbilities });
    },
  },
  methods: {
    tokenStyleFor(tool) {
      if (tool.source !== 'mcp') return null;
      return {
        borderColor: 'var(--gl-feedback-warning-border-color)',
        backgroundColor: 'var(--gl-feedback-warning-background-color)',
      };
    },
  },
  toolsDocsLink: helpPagePath('user/duo_agent_platform/agents/tools'),
};
</script>

<template>
  <div>
    <h2 class="gl-heading-3">
      {{ s__('AICatalog|Agent configuration') }}
    </h2>
    <div class="gl-flex gl-flex-col gl-gap-7">
      <form-section is-display data-testid="configuration-section">
        <ai-catalog-item-field
          v-if="!isThirdPartyFlow"
          :title="s__('AICatalog|System prompt')"
          data-testid="system-prompt-field"
        >
          <div class="gl-border gl-mt-3 gl-rounded-default gl-bg-default gl-p-3">
            <pre class="gl-m-0 gl-whitespace-pre-wrap"><gl-truncate-text
            :lines="20"
            :show-more-text="__('Show more')"
            :show-less-text="__('Show less')"
            :toggle-button-props="$options.truncateTextToggleButtonProps"
            class="gl-flex gl-flex-col gl-items-start gl-gap-3"
          >{{ systemPrompt }}</gl-truncate-text></pre>
          </div>
        </ai-catalog-item-field>
        <ai-catalog-item-field :title="s__('AICatalog|Type')" :value="typeField" />
        <template v-if="isThirdPartyFlow">
          <trigger-field v-if="hasProjectConfiguration" :item="item" />
          <ai-catalog-item-field :title="s__('AICatalog|YAML configuration')">
            <form-flow-definition :value="definition" read-only class="gl-mt-3" />
          </ai-catalog-item-field>
        </template>
        <template v-else>
          <ai-catalog-item-field :title="s__('AICatalog|Tools')">
            <p class="gl-text-subtle">
              <gl-sprintf
                :message="
                  s__(
                    'AICatalog|Tools are built and maintained by GitLab. %{linkStart}What are tools?%{linkEnd}',
                  )
                "
              >
                <template #link="{ content }">
                  <gl-link :href="$options.toolsDocsLink">{{ content }}</gl-link>
                </template>
              </gl-sprintf>
            </p>
            <span v-if="tools.length === 0" class="gl-text-subtle">
              {{ __('None') }}
            </span>
            <div v-else class="gl-mt-3 gl-flex gl-flex-wrap gl-gap-2 gl-whitespace-nowrap">
              <gl-token
                v-for="tool in tools"
                :key="tool.key"
                view-only
                class="gl-min-h-7 gl-cursor-default gl-px-3 gl-py-1"
                :style="tokenStyleFor(tool)"
              >
                <span class="gl-flex gl-items-center gl-gap-2">
                  <span
                    v-gl-tooltip
                    :title="tool.description"
                    data-testid="tool-description-tooltip"
                    >{{ tool.title }}</span
                  >
                  <span v-if="tool.source === 'mcp'" class="gl-sr-only">
                    {{ s__('AICatalog|GitLab MCP') }}
                  </span>
                  <!-- eslint-disable @gitlab/vue-require-i18n-attribute-strings -->
                  <img
                    v-if="tool.source === 'mcp' && tool.iconUrl"
                    v-gl-tooltip="s__('AICatalog|GitLab MCP')"
                    :src="tool.iconUrl"
                    alt=""
                    class="gl-ml-1 gl-h-4 gl-w-4 gl-rounded-sm"
                    aria-hidden="true"
                  />
                  <!-- eslint-enable @gitlab/vue-require-i18n-attribute-strings -->
                </span>
              </gl-token>
            </div>
          </ai-catalog-item-field>
          <ai-catalog-item-field v-if="canReadMcpServers" :title="s__('AICatalog|MCP servers')">
            <p class="gl-text-subtle">
              {{ s__('AICatalog|MCP servers allow your agent to connect with external tools.') }}
            </p>
            <span v-if="mcpServers.length === 0" class="gl-text-subtle">
              {{ __('None') }}
            </span>
            <div v-else class="gl-mt-3 gl-flex gl-flex-wrap gl-gap-2 gl-whitespace-nowrap">
              <span
                v-for="server in mcpServers"
                :key="server.id"
                v-gl-tooltip
                :title="server.description"
                data-testid="mcp-server-description-tooltip"
              >
                <gl-token view-only class="gl-cursor-default">
                  {{ server.name }}
                </gl-token>
              </span>
            </div>
          </ai-catalog-item-field>
        </template>
      </form-section>
      <form-section v-if="serviceAccount" :title="s__('AICatalog|Service account')" is-display>
        <ai-catalog-item-field-service-account
          :service-account="serviceAccount"
          :item-type="item.itemType"
          data-testid="service-account-field"
        />
      </form-section>
    </div>
  </div>
</template>
