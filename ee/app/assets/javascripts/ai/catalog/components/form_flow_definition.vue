<script>
import { GlButton, GlTooltipDirective } from '@gitlab/ui';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import SourceEditor from '~/vue_shared/components/source_editor.vue';
import { AgentReferenceExtension } from '../flow_editor/agent_reference_ext';
import aiCatalogAgentReferencesQuery from '../graphql/queries/ai_catalog_agent_references.query.graphql';

const AGENT_REFERENCES_PAGE_SIZE = 100;

export default {
  name: 'FormFlowConfiguration',
  components: {
    ClipboardButton,
    GlButton,
    SourceEditor,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [glFeatureFlagsMixin()],
  apollo: {
    agents: {
      query: aiCatalogAgentReferencesQuery,
      variables() {
        return { first: AGENT_REFERENCES_PAGE_SIZE };
      },
      skip() {
        return !this.agentReferencesEnabled;
      },
      update(data) {
        return (data?.aiCatalogItems?.nodes ?? []).map((node) => ({
          id: String(getIdFromGraphQLId(node.id)),
          name: node.name,
        }));
      },
      error() {
        this.agents = [];
      },
    },
  },
  props: {
    readOnly: {
      type: Boolean,
      required: false,
      default: false,
    },
    value: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['input'],
  data() {
    return {
      agents: [],
    };
  },
  computed: {
    editorOptions() {
      return {
        padding: { top: 4 },
        readOnly: this.readOnly,
        // The word highlight competes with the agent reference underline.
        ...(this.agentReferencesEnabled && { occurrencesHighlight: false }),
      };
    },
    agentReferencesEnabled() {
      return Boolean(this.glFeatures.aiCatalogFlowAgentReferences);
    },
    editorExtensions() {
      if (!this.agentReferencesEnabled) return [];

      return [
        {
          definition: AgentReferenceExtension,
          setupOptions: { getAgents: () => this.agents },
        },
      ];
    },
  },
  methods: {
    onInput(val) {
      this.$emit('input', val);
    },
    clearValue(event) {
      const editor = this.$refs.editor.getEditor();
      if (editor) {
        const model = editor.getModel();
        if (model) {
          editor.executeEdits('clear-button', [
            {
              range: model.getFullModelRange(),
              text: '',
            },
          ]);
          if (typeof event === 'undefined' || event.detail !== 0) {
            // only focus when the user clicked the button with mouse or touchpad
            // when user hit enter to click the button, the focus stays there.
            editor.focus();
          }
        }
      }
    },
  },
  configFile: 'config.yaml',
};
</script>

<template>
  <div class="gl-rounded-lg gl-border-1 gl-border-solid gl-border-default">
    <div
      class="gl-flex gl-justify-between gl-rounded-t-lg gl-border-b-1 gl-border-default gl-bg-subtle gl-px-5 gl-py-3 gl-border-b-solid"
      data-testid="flow-definition-header"
    >
      <strong>{{ $options.configFile }}</strong>
      <div class="gl-flex gl-gap-2">
        <clipboard-button
          :text="value"
          :title="s__('AICatalog|Copy configuration')"
          category="secondary"
          size="small"
        />
        <gl-button
          v-if="!readOnly"
          v-gl-tooltip
          variant="default"
          category="secondary"
          size="small"
          icon="clear-all"
          :title="s__('AICatalog|Clear editor')"
          :aria-label="s__('AICatalog|Clear editor')"
          data-testid="flow-definition-clear-button"
          @click="clearValue"
        />
      </div>
    </div>
    <source-editor
      ref="editor"
      :value="value"
      file-name="*.yaml"
      :editor-options="editorOptions"
      :extensions="editorExtensions"
      :use-dynamic-height="false"
      class="gl-overflow-hidden gl-break-normal gl-rounded-b-lg"
      @input="onInput"
    />
  </div>
</template>
