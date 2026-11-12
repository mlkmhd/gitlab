import { GlFormCheckbox, GlFormCheckboxGroup } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoGroupAgentPicker from 'ee/ai/settings/readiness/components/duo_group_agent_picker.vue';

const STATUSES = [
  { reference: 'planner', name: 'Planner', description: 'Plans work.', enabled: true },
  { reference: 'security', name: 'Security Analyst', description: 'Finds risks.', enabled: null },
  { reference: 'data', name: 'Data Analyst', description: 'Reads data.', enabled: false },
];

describe('DuoGroupAgentPicker', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(DuoGroupAgentPicker, {
      propsData: { statuses: STATUSES, ...props },
      stubs: { GlFormCheckboxGroup },
    });
  };

  const findSelectAll = () => wrapper.findComponentByTestId('foundational-agent-select-all');
  const findGroup = () => wrapper.findComponent(GlFormCheckboxGroup);
  const findAgentCheckboxes = () =>
    wrapper
      .findAllComponents(GlFormCheckbox)
      .wrappers.filter((box) => box.attributes('data-testid') === 'foundational-agent-checkbox');

  it('points the checkboxes at the note they are described by', () => {
    createComponent({ props: { describedBy: 'agents-note' } });

    expect(findSelectAll().attributes('aria-describedby')).toBe('agents-note');
    expect(findAgentCheckboxes().map((box) => box.attributes('aria-describedby'))).toEqual([
      'agents-note',
      'agents-note',
      'agents-note',
    ]);
  });

  it('groups one checkbox per agent under the row title, checked unless the agent opted out', () => {
    createComponent();

    expect(findGroup().attributes('aria-label')).toBe('Foundational agents');
    expect(findGroup().props('checked')).toEqual(['planner', 'security']);
    expect(findAgentCheckboxes().map((box) => box.props('value'))).toEqual([
      'planner',
      'security',
      'data',
    ]);
    expect(findAgentCheckboxes()[1].text()).toContain('Security Analyst');
    expect(findAgentCheckboxes()[1].text()).toContain('Finds risks.');
  });

  it.each`
    statuses                                                   | checked  | indeterminate
    ${STATUSES}                                                | ${false} | ${true}
    ${STATUSES.map((agent) => ({ ...agent, enabled: true }))}  | ${true}  | ${false}
    ${STATUSES.map((agent) => ({ ...agent, enabled: false }))} | ${false} | ${false}
  `(
    'renders Select all as checked=$checked indeterminate=$indeterminate',
    ({ statuses, checked, indeterminate }) => {
      createComponent({ props: { statuses } });

      expect(findSelectAll().props()).toMatchObject({ checked, indeterminate });
    },
  );

  it('disables every checkbox', () => {
    createComponent({ props: { disabled: true } });

    expect(findSelectAll().props('disabled')).toBe(true);
    expect(findGroup().props('disabled')).toBe(true);
  });

  it('emits the statuses with every agent set explicitly from the checked references', () => {
    createComponent();

    findGroup().vm.$emit('change', ['planner']);
    findGroup().vm.$emit('change', ['planner', 'security', 'data']);

    expect(wrapper.emitted('change')).toEqual([
      [[STATUSES[0], { ...STATUSES[1], enabled: false }, { ...STATUSES[2], enabled: false }]],
      [STATUSES.map((agent) => ({ ...agent, enabled: true }))],
    ]);
  });

  it('emits every agent set explicitly from Select all', () => {
    createComponent();

    findSelectAll().vm.$emit('change', true);
    findSelectAll().vm.$emit('change', false);

    expect(wrapper.emitted('change')).toEqual([
      [STATUSES.map((agent) => ({ ...agent, enabled: true }))],
      [STATUSES.map((agent) => ({ ...agent, enabled: false }))],
    ]);
  });
});
