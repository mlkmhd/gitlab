import { shallowMount } from '@vue/test-utils';
import { GlFormCheckbox, GlFormCheckboxGroup } from '@gitlab/ui';
import FoundationalFlowSelector from 'ee/ai/settings/components/foundational_flow_selector.vue';

describe('FoundationalFlowSelector', () => {
  let wrapper;

  const mockFlows = [
    {
      reference: 'code_review/v1',
      name: 'Code Review Flow',
      description: 'Automated code review assistant',
    },
    {
      reference: 'bug_triage/v1',
      name: 'Bug Triage Flow',
      description: 'Automatically triages and categorizes bugs',
    },
    {
      reference: 'documentation/v1',
      name: 'Documentation Flow',
      description: 'Generates documentation from code',
    },
  ];

  const createWrapper = (props = {}, provide = {}) => {
    return shallowMount(FoundationalFlowSelector, {
      propsData: {
        value: [],
        ...props,
      },
      provide: {
        availableFoundationalFlows: mockFlows,
        ...provide,
      },
      stubs: {
        GlFormCheckbox,
        GlFormCheckboxGroup,
      },
    });
  };

  const findGroup = () => wrapper.findComponent(GlFormCheckboxGroup);
  const findAllCheckboxes = () => wrapper.findAllComponents(GlFormCheckbox);
  const findCheckboxAt = (index) => findAllCheckboxes().at(index);

  describe('component rendering', () => {
    beforeEach(() => {
      wrapper = createWrapper();
    });

    it('groups the checkboxes under the row title', () => {
      expect(findGroup().attributes('aria-label')).toBe('Foundational flows');
      expect(findGroup().classes()).toEqual(expect.arrayContaining(['gl-ml-6', 'gl-mt-3']));
    });

    it('renders a checkbox for each available flow, valued by its reference', () => {
      expect(findAllCheckboxes()).toHaveLength(3);
      expect(findAllCheckboxes().wrappers.map((box) => box.props('value'))).toEqual([
        'code_review/v1',
        'bug_triage/v1',
        'documentation/v1',
      ]);
    });

    it('renders flow names correctly', () => {
      expect(findCheckboxAt(0).text()).toContain('Code Review Flow');
      expect(findCheckboxAt(1).text()).toContain('Bug Triage Flow');
      expect(findCheckboxAt(2).text()).toContain('Documentation Flow');
    });

    it('renders flow descriptions correctly', () => {
      expect(findCheckboxAt(0).text()).toContain('Automated code review assistant');
      expect(findCheckboxAt(1).text()).toContain('Automatically triages and categorizes bugs');
      expect(findCheckboxAt(2).text()).toContain('Generates documentation from code');
    });

    it('renders descriptionHtml when provided', () => {
      const flowsWithHtml = [
        {
          reference: 'code_review/v1',
          name: 'Code Review Flow',
          description: 'Automated code review assistant',
          descriptionHtml:
            '<p>Automated code review assistant. <a href="https://example.com">Learn more</a>.</p>',
        },
      ];

      wrapper = createWrapper({}, { availableFoundationalFlows: flowsWithHtml });

      expect(findCheckboxAt(0).html()).toContain('<a href="https://example.com">Learn more</a>');
    });

    it('sets correct data-testid on checkboxes', () => {
      const checkboxes = wrapper.findAll('[data-testid="foundational-flow-checkbox"]');
      expect(checkboxes).toHaveLength(3);
    });
  });

  describe('when no flows are available', () => {
    beforeEach(() => {
      wrapper = createWrapper({}, { availableFoundationalFlows: [] });
    });

    it('renders no checkboxes', () => {
      expect(findAllCheckboxes()).toHaveLength(0);
    });
  });

  describe('checkbox selection state', () => {
    it('checks the selected flows through the group', () => {
      wrapper = createWrapper({ value: ['code_review/v1', 'documentation/v1'] });

      expect(findGroup().props('checked')).toEqual(['code_review/v1', 'documentation/v1']);
      expect(findCheckboxAt(0).find('input').element.checked).toBe(true);
      expect(findCheckboxAt(1).find('input').element.checked).toBe(false);
      expect(findCheckboxAt(2).find('input').element.checked).toBe(true);
    });

    it('checks nothing when value is empty', () => {
      wrapper = createWrapper({ value: [] });

      findAllCheckboxes().wrappers.forEach((checkbox) => {
        expect(checkbox.find('input').element.checked).toBe(false);
      });
    });
  });

  describe('disabled state', () => {
    it('enables all checkboxes by default', () => {
      wrapper = createWrapper();

      findAllCheckboxes().wrappers.forEach((checkbox) => {
        expect(checkbox.find('input').element.disabled).toBe(false);
      });
    });

    it('disables all checkboxes through the group', () => {
      wrapper = createWrapper({ disabled: true });

      expect(findGroup().props('disabled')).toBe(true);
      findAllCheckboxes().wrappers.forEach((checkbox) => {
        expect(checkbox.find('input').element.disabled).toBe(true);
      });
    });
  });

  describe('checkbox interactions', () => {
    it('emits the references the group reports as checked', () => {
      wrapper = createWrapper({ value: ['code_review/v1'] });

      findGroup().vm.$emit('input', ['code_review/v1', 'bug_triage/v1']);
      findGroup().vm.$emit('input', []);

      expect(wrapper.emitted('input')).toEqual([[['code_review/v1', 'bug_triage/v1']], [[]]]);
    });

    it('emits the new selection when a checkbox is clicked', async () => {
      wrapper = createWrapper({ value: ['code_review/v1'] });

      await findCheckboxAt(1).find('input').setChecked(true);

      expect(wrapper.emitted('input')).toEqual([[['code_review/v1', 'bug_triage/v1']]]);
    });
  });

  describe('edge cases', () => {
    it('handles flow with missing description', () => {
      const flowsWithoutDescription = [
        {
          reference: 'flow_without_desc/v1',
          name: 'Flow Without Description',
          description: undefined,
        },
      ];

      wrapper = createWrapper({}, { availableFoundationalFlows: flowsWithoutDescription });

      expect(findCheckboxAt(0).text()).toContain('Flow Without Description');
    });

    it('handles flow with empty description', () => {
      const flowsWithEmptyDescription = [
        {
          reference: 'flow_with_empty_desc/v1',
          name: 'Flow With Empty Description',
          description: '',
        },
      ];

      wrapper = createWrapper({}, { availableFoundationalFlows: flowsWithEmptyDescription });

      expect(wrapper.exists()).toBe(true);
    });
  });

  describe('when described by a note', () => {
    it('points every checkbox at it', () => {
      wrapper = createWrapper({ describedBy: 'flows-note' });

      expect(wrapper.findAll('[aria-describedby="flows-note"]')).toHaveLength(3);
    });
  });
});
