import { shallowMount } from '@vue/test-utils';
import { GlFormCheckbox, GlFormGroup } from '@gitlab/ui';
import DuoWorkflowFileAttachmentsForm from 'ee/ai/settings/components/duo_workflow_file_attachments_form.vue';

describe('DuoWorkflowFileAttachmentsForm', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMount(DuoWorkflowFileAttachmentsForm, {
      propsData: {
        duoWorkflowFileAttachmentsEnabled: false,
        ...props,
      },
      stubs: {
        GlFormCheckbox,
        GlFormGroup,
      },
    });
  };

  const findFormGroup = () => wrapper.findComponent(GlFormGroup);
  const findCheckbox = () => wrapper.findComponent(GlFormCheckbox);
  const findCheckboxLabel = () => findCheckbox().find('span');

  beforeEach(() => {
    createComponent();
  });

  it('renders the section title', () => {
    expect(findFormGroup().attributes('label')).toBe('File attachments');
  });

  it('renders the checkbox label', () => {
    expect(findCheckboxLabel().text()).toBe('Allow file attachments');
  });

  it('renders the help text', () => {
    expect(findCheckbox().text()).toContain(
      'Users can attach files to GitLab Duo Chat messages. GitLab sends attached files to the AI model.',
    );
  });

  it('exposes the checkbox under a stable test id', () => {
    expect(
      wrapper.find('[data-testid="duo-workflow-file-attachments-enabled-checkbox"]').exists(),
    ).toBe(true);
  });

  it.each`
    duoWorkflowFileAttachmentsEnabled | description
    ${true}                           | ${'checked'}
    ${false}                          | ${'unchecked'}
  `(
    'renders the checkbox as $description when duoWorkflowFileAttachmentsEnabled is $duoWorkflowFileAttachmentsEnabled',
    ({ duoWorkflowFileAttachmentsEnabled }) => {
      createComponent({ props: { duoWorkflowFileAttachmentsEnabled } });

      expect(findCheckbox().props('checked')).toBe(duoWorkflowFileAttachmentsEnabled);
    },
  );

  it.each([[true], [false]])('sets the checkbox disabled state to %p', (disabledCheckbox) => {
    createComponent({ props: { disabledCheckbox } });

    expect(findCheckbox().props('disabled')).toBe(disabledCheckbox);
  });

  it.each([[true], [false]])('emits change with %p when the checkbox is toggled', (value) => {
    findCheckbox().vm.$emit('change', value);

    expect(wrapper.emitted('change')).toEqual([[value]]);
  });
});
