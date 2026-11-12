import { GlAlert } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AgentUnavailableAlert from 'ee/ai/duo_agentic_chat/components/agent_unavailable_alert.vue';

describe('AgentUnavailableAlert', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(AgentUnavailableAlert, {
      propsData: {
        agentName: 'Data Analyst',
        defaultNamespaceGoverns: true,
        isSaas: true,
        preferencesPath: '/-/profile/preferences#duo',
        ...props,
      },
      stubs: { GlAlert },
    });
  };

  const findAlert = () => wrapper.findComponent(GlAlert);
  const findMessage = () => wrapper.find('p');
  const findPreferencesLink = () =>
    wrapper.findComponentByTestId('agent-unavailable-preferences-link');
  const findHelpLink = () => wrapper.findComponentByTestId('agent-unavailable-help-link');

  describe('when the default namespace decides', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders a non-dismissible warning alert', () => {
      expect(findAlert().props('variant')).toBe('warning');
      expect(findAlert().props('dismissible')).toBe(false);
    });

    it('names the agent and the default namespace', () => {
      expect(findMessage().text()).toBe(
        "The Data Analyst agent isn't available for your default GitLab Duo namespace. Messages in this chat go to the GitLab Duo agent.",
      );
    });

    it('links to the Duo preferences', () => {
      expect(findPreferencesLink().attributes('href')).toBe('/-/profile/preferences#duo');
      expect(findPreferencesLink().text()).toBe('Switch namespace');
      expect(findHelpLink().exists()).toBe(false);
    });
  });

  describe("when the page's group decides", () => {
    beforeEach(() => {
      createComponent({ props: { defaultNamespaceGoverns: false } });
    });

    it('names the agent and the group or project', () => {
      expect(findMessage().text()).toBe(
        "The Data Analyst agent isn't available in this group or project. Messages in this chat go to the GitLab Duo agent.",
      );
    });

    it('links to the foundational agents docs instead of the preferences', () => {
      expect(findHelpLink().exists()).toBe(true);
      expect(findPreferencesLink().exists()).toBe(false);
    });
  });

  describe('without an agent name', () => {
    it.each`
      props                                 | expectedMessage
      ${{}}                                 | ${"The requested agent isn't available for your default GitLab Duo namespace. Messages in this chat go to the GitLab Duo agent."}
      ${{ defaultNamespaceGoverns: false }} | ${"The requested agent isn't available in this group or project. Messages in this chat go to the GitLab Duo agent."}
      ${{ isSaas: false }}                  | ${"The requested agent isn't available on this instance. Contact your administrator. Messages in this chat go to the GitLab Duo agent."}
    `('shows "$expectedMessage" for $props', ({ props, expectedMessage }) => {
      createComponent({ props: { agentName: '', ...props } });

      expect(findMessage().text()).toBe(expectedMessage);
    });
  });

  describe.each`
    defaultNamespaceGoverns
    ${false}
    ${true}
  `(
    'on a self-managed instance with defaultNamespaceGoverns $defaultNamespaceGoverns',
    ({ defaultNamespaceGoverns }) => {
      beforeEach(() => {
        createComponent({ props: { isSaas: false, defaultNamespaceGoverns } });
      });

      it('names the agent and the instance', () => {
        expect(findMessage().text()).toBe(
          "The Data Analyst agent isn't available on this instance. Contact your administrator. Messages in this chat go to the GitLab Duo agent.",
        );
      });

      it('links to the foundational agents docs instead of the preferences', () => {
        expect(findHelpLink().attributes('href')).toBe(
          '/help/user/duo_agent_platform/agents/foundational_agents/_index#turn-foundational-agents-on-or-off',
        );
        expect(findPreferencesLink().exists()).toBe(false);
      });
    },
  );

  describe('without a preferences path', () => {
    beforeEach(() => {
      createComponent({ props: { preferencesPath: '' } });
    });

    it('links to the foundational agents docs', () => {
      expect(findHelpLink().exists()).toBe(true);
      expect(findPreferencesLink().exists()).toBe(false);
    });
  });
});
