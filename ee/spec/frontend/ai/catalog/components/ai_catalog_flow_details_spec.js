import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AiCatalogFlowDetails from 'ee/ai/catalog/components/ai_catalog_flow_details.vue';
import AiCatalogItemField from 'ee/ai/catalog/components/ai_catalog_item_field.vue';
import FormFlowDefinition from 'ee/ai/catalog/components/form_flow_definition.vue';
import FormSection from 'ee/ai/catalog/components/form_section.vue';
import TriggerField from 'ee/ai/catalog/components/trigger_field.vue';
import { VERSION_LATEST, VERSION_PINNED } from 'ee/ai/catalog/constants';
import {
  mockFlow,
  mockFlowConfigurationForProject,
  mockServiceAccount,
  mockItemConfigurationForGroup,
} from '../mock_data';

describe('AiCatalogFlowDetails', () => {
  let wrapper;

  const mockFoundationalFlow = {
    ...mockFlow,
    foundational: true,
    verificationLevel: 'GITLAB_MAINTAINED',
    configurationForGroup: mockItemConfigurationForGroup,
  };

  const defaultProps = {
    item: mockFlow,
    versionKey: VERSION_LATEST,
  };

  const createComponent = ({ props = {}, provide } = {}) => {
    wrapper = shallowMountExtended(AiCatalogFlowDetails, {
      propsData: {
        ...defaultProps,
        ...props,
      },
      provide,
    });
  };

  const findAllSections = () => wrapper.findAllComponents(FormSection);
  const findSection = (index) => findAllSections().at(index);
  const findAllFieldsForSection = (index) =>
    findSection(index).findAllComponents(AiCatalogItemField);
  const findTriggerField = () => wrapper.findComponent(TriggerField);
  const findServiceAccountField = () => wrapper.findComponentByTestId('service-account-field');
  const findConfigurationField = () => wrapper.findComponentByTestId('configuration-field');
  const findConfigurationSection = () => wrapper.findComponentByTestId('configuration-section');

  describe('template', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the Configuration section', () => {
      expect(findAllSections()).toHaveLength(1);
      expect(findSection(0).attributes('data-testid')).toBe('configuration-section');
    });
  });

  describe('renders "Configuration" details', () => {
    describe('default', () => {
      beforeEach(() => {
        createComponent();
      });

      it('renders latestVersion flow definition', () => {
        expect(findConfigurationField().props('title')).toBe('YAML configuration');
        expect(findConfigurationField().findComponent(FormFlowDefinition).props('value')).toBe(
          mockFlow.latestVersion.definition,
        );
      });

      it('does not render triggers field', () => {
        const configurationFields = findAllFieldsForSection(0);
        expect(configurationFields).toHaveLength(1);
      });
    });

    describe('when configurationForProject exists', () => {
      beforeEach(() => {
        createComponent({
          props: {
            item: {
              ...mockFlow,
              configurationForProject: {
                ...mockFlowConfigurationForProject,
              },
            },
            versionKey: VERSION_PINNED,
          },
        });
      });

      it('renders the trigger field', () => {
        expect(findTriggerField().exists()).toBe(true);
      });

      it('renders pinnedItemVersion flow definition', () => {
        expect(findConfigurationField().findComponent(FormFlowDefinition).props('value')).toBe(
          mockFlowConfigurationForProject.pinnedItemVersion.definition,
        );
      });
    });

    describe('when configurationForGroup.serviceAccount exists', () => {
      beforeEach(() => {
        createComponent({
          props: {
            item: {
              ...mockFlow,
              configurationForGroup: {
                serviceAccount: mockServiceAccount,
              },
            },
          },
        });
      });

      it('renders 2 sections', () => {
        expect(findAllSections()).toHaveLength(2);
        expect(findSection(0).attributes('data-testid')).toBe('configuration-section');
        expect(findSection(1).attributes('title')).toBe('Service account');
      });

      it('renders service account field', () => {
        expect(findServiceAccountField().props()).toMatchObject({
          serviceAccount: mockServiceAccount,
          itemType: 'FLOW',
        });
      });

      it('forwards foundationalFlowReference to the service account field', () => {
        createComponent({
          props: {
            item: {
              ...mockFlow,
              foundationalFlowReference: 'code_review/v1',
              configurationForGroup: {
                serviceAccount: mockServiceAccount,
              },
            },
          },
        });

        expect(findServiceAccountField().props('foundationalFlowReference')).toBe('code_review/v1');
      });
    });
  });

  describe('when the item is foundational', () => {
    describe('and has configurationForGroup', () => {
      beforeEach(() => {
        createComponent({
          props: {
            item: mockFoundationalFlow,
          },
        });
      });

      it('does not render the YAML configuration field', () => {
        expect(findConfigurationField().exists()).toBe(false);
      });

      it('does not render the Configuration section on a project page', () => {
        expect(findConfigurationSection().exists()).toBe(false);
        expect(findTriggerField().exists()).toBe(false);
      });

      describe('on a group page', () => {
        beforeEach(() => {
          createComponent({
            props: { item: mockFoundationalFlow },
            provide: { isGroupNamespace: true },
          });
        });

        it('renders the Configuration section with triggers but no YAML configuration', () => {
          expect(findConfigurationSection().exists()).toBe(true);
          expect(findTriggerField().exists()).toBe(true);
          expect(findConfigurationField().exists()).toBe(false);
        });
      });
    });

    describe('and has no content in Configuration section', () => {
      beforeEach(() => {
        createComponent({
          props: {
            item: {
              ...mockFoundationalFlow,
              configurationForGroup: null,
              configurationForProject: null,
            },
          },
        });
      });

      it('does not render the Configuration section', () => {
        expect(findConfigurationSection().exists()).toBe(false);
      });

      it('does not render an empty "Flow configuration" heading', () => {
        expect(wrapper.find('h2').exists()).toBe(false);
      });
    });

    describe('and is the Code Review foundational flow', () => {
      beforeEach(() => {
        createComponent({
          props: {
            item: {
              ...mockFoundationalFlow,
              foundationalFlowReference: 'code_review/v1',
              configurationForProject: mockFlowConfigurationForProject,
            },
          },
        });
      });

      it('does not render the Configuration section even with a project configuration', () => {
        expect(findConfigurationSection().exists()).toBe(false);
      });
    });
  });
});
