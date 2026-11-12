import { shallowMount } from '@vue/test-utils';
import { GlFormCheckbox, GlLink, GlSprintf } from '@gitlab/ui';
import ExecutionEnvironmentSandboxForm from 'ee/ai/settings/components/execution_environment_sandbox_form.vue';

describe('ExecutionEnvironmentSandboxForm', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMount(ExecutionEnvironmentSandboxForm, {
      propsData: {
        requireSandbox: false,
        ...props,
      },
      stubs: {
        GlFormCheckbox,
        GlSprintf,
      },
    });
  };

  const findHeading = () => wrapper.find('h3');
  const findCheckbox = () => wrapper.findComponent(GlFormCheckbox);
  const findCheckboxLabel = () => findCheckbox().find('span');
  const findHelpLink = () => wrapper.findComponent(GlLink);

  describe('default', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the section heading', () => {
      expect(findHeading().text()).toBe('Execution environment sandbox');
    });

    it('renders the checkbox label', () => {
      expect(findCheckboxLabel().text()).toBe("Don't run flows when the sandbox is unavailable");
    });

    it('renders the help text', () => {
      expect(findCheckbox().text()).toContain(
        'If the sandbox is unavailable, flows that run on GitLab Runner fail instead of running without network and file system isolation. Learn more about requiring the sandbox.',
      );
    });

    it('links the help text to the docs', () => {
      expect(findHelpLink().text()).toBe('Learn more about requiring the sandbox');
      expect(findHelpLink().attributes('href')).toBe(
        '/help/user/duo_agent_platform/environment_sandbox#require-flows-to-run-in-the-sandbox',
      );
      expect(findHelpLink().attributes('target')).toBe('_blank');
    });

    it('renders the checkbox as unchecked', () => {
      expect(findCheckbox().props('checked')).toBe(false);
    });

    it('renders the checkbox as enabled', () => {
      expect(findCheckbox().props('disabled')).toBe(false);
    });
  });

  describe('when requireSandbox is true', () => {
    beforeEach(() => {
      createComponent({ props: { requireSandbox: true } });
    });

    it('renders the checkbox as checked', () => {
      expect(findCheckbox().props('checked')).toBe(true);
    });
  });

  describe('when disabledCheckbox is true', () => {
    beforeEach(() => {
      createComponent({ props: { disabledCheckbox: true } });
    });

    it('renders the checkbox as disabled', () => {
      expect(findCheckbox().props('disabled')).toBe(true);
    });
  });

  describe('when the checkbox is toggled', () => {
    beforeEach(() => {
      createComponent();
    });

    it.each([true, false])('emits change with %p', (value) => {
      findCheckbox().vm.$emit('change', value);

      expect(wrapper.emitted('change')).toEqual([[value]]);
    });
  });
});
