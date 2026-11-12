import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import FormFlowDefinition from 'ee/ai/catalog/components/form_flow_definition.vue';
import { AgentReferenceExtension } from 'ee/ai/catalog/flow_editor/agent_reference_ext';
import aiCatalogAgentReferencesQuery from 'ee/ai/catalog/graphql/queries/ai_catalog_agent_references.query.graphql';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import SourceEditor from '~/vue_shared/components/source_editor.vue';
import { AGENTS, AGENTS_QUERY_NODES } from '../flow_editor/mock_data';

Vue.use(VueApollo);

const agentReferencesResponse = {
  data: {
    aiCatalogItems: { nodes: AGENTS_QUERY_NODES },
  },
};

describe('FormFlowDefinition', () => {
  let wrapper;
  let agentReferencesHandler;

  const defaultProps = {
    value: 'some YAML content',
    readOnly: false,
  };

  const createComponent = ({ props = {}, glFeatures = {} } = {}) => {
    agentReferencesHandler = jest.fn().mockResolvedValue(agentReferencesResponse);
    wrapper = shallowMountExtended(FormFlowDefinition, {
      apolloProvider: createMockApollo([[aiCatalogAgentReferencesQuery, agentReferencesHandler]]),
      propsData: {
        ...defaultProps,
        ...props,
      },
      provide: { glFeatures },
    });
  };

  const findHeader = () => wrapper.findByTestId('flow-definition-header');
  const findClipboardButton = () => wrapper.findComponent(ClipboardButton);
  const findClearButton = () => wrapper.findComponentByTestId('flow-definition-clear-button');
  const findSourceEditor = () => wrapper.findComponent(SourceEditor);

  describe('default', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders header with clipboard and clear button', () => {
      expect(findHeader().text()).toBe('config.yaml');
      expect(findClipboardButton().props('text')).toBe(defaultProps.value);
      expect(findClearButton().exists()).toBe(true);
    });

    it('renders source editor with correct props', () => {
      expect(findSourceEditor().props('value')).toBe(defaultProps.value);
      expect(findSourceEditor().props('fileName')).toBe('*.yaml');
      expect(findSourceEditor().props('editorOptions')).toEqual({
        padding: { top: 4 },
        readOnly: defaultProps.readOnly,
      });
    });

    it('emits input event when value is changed', async () => {
      await findSourceEditor().vm.$emit('input', 'updated YAML content');

      expect(wrapper.emitted('input')).toEqual([['updated YAML content']]);
    });
  });

  describe('agent references', () => {
    describe('with the ai_catalog_flow_agent_references flag on', () => {
      beforeEach(async () => {
        createComponent({ glFeatures: { aiCatalogFlowAgentReferences: true } });
        await waitForPromises();
      });

      it('turns off the word highlight that competes with the underline', () => {
        expect(findSourceEditor().props('editorOptions')).toMatchObject({
          occurrencesHighlight: false,
        });
      });

      it('loads the agents the user can see', () => {
        expect(agentReferencesHandler).toHaveBeenCalledWith({ first: 100 });
      });

      it('gives the editor the extension with the agents it loaded', () => {
        const [extension] = findSourceEditor().props('extensions');

        expect(extension.definition).toBe(AgentReferenceExtension);
        expect(extension.setupOptions.getAgents()).toEqual(AGENTS);
      });
    });

    it('does not load or extend when the flag is off', () => {
      createComponent({ glFeatures: { aiCatalogFlowAgentReferences: false } });

      expect(agentReferencesHandler).not.toHaveBeenCalled();
      expect(findSourceEditor().props('extensions')).toEqual([]);
    });

    it('loads the agents and extends read-only too, for the underline and the hover', async () => {
      createComponent({
        props: { readOnly: true },
        glFeatures: { aiCatalogFlowAgentReferences: true },
      });
      await waitForPromises();

      expect(agentReferencesHandler).toHaveBeenCalled();
      expect(findSourceEditor().props('extensions')).toHaveLength(1);
    });
  });

  describe('when readOnly is true', () => {
    beforeEach(() => {
      createComponent({ props: { readOnly: true } });
    });

    it('does not render clear button', () => {
      expect(findClearButton().exists()).toBe(false);
    });
  });

  describe('clear button', () => {
    let mockEditor;
    let mockModel;

    beforeEach(() => {
      createComponent();

      mockModel = {
        getFullModelRange: jest.fn().mockReturnValue('full-range'),
      };

      mockEditor = {
        getModel: jest.fn().mockReturnValue(mockModel),
        executeEdits: jest.fn(),
        focus: jest.fn(),
      };

      findSourceEditor().vm.getEditor = jest.fn().mockReturnValue(mockEditor);
    });

    it('clears the editor content using executeEdits', async () => {
      await findClearButton().vm.$emit('click');

      expect(mockEditor.getModel).toHaveBeenCalled();
      expect(mockModel.getFullModelRange).toHaveBeenCalled();
      expect(mockEditor.executeEdits).toHaveBeenCalledWith('clear-button', [
        {
          range: 'full-range',
          text: '',
        },
      ]);
    });

    describe('editor focus behavior', () => {
      it('focuses the editor when clicked with mouse (event detail is not 0)', async () => {
        const mouseClickEvent = new MouseEvent('click', { detail: 1 });
        await findClearButton().vm.$emit('click', mouseClickEvent);

        expect(mockEditor.focus).toHaveBeenCalled();
      });

      it('does not focus the editor when activated with keyboard (event detail is 0)', async () => {
        const keyboardEvent = new MouseEvent('click', { detail: 0 });
        await findClearButton().vm.$emit('click', keyboardEvent);

        expect(mockEditor.focus).not.toHaveBeenCalled();
      });

      it('focuses the editor when no event is passed', async () => {
        await findClearButton().vm.$emit('click');

        expect(mockEditor.focus).toHaveBeenCalled();
      });
    });
  });
});
