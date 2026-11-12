import Vue from 'vue';
import { PiniaVuePlugin } from 'pinia';
import { createTestingPinia } from '@pinia/testing';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import IntegrationForm from '~/integrations/edit/components/integration_form.vue';
import { INTEGRATION_FORM_TYPE_SLACK } from '~/integrations/constants';
import { useIntegrationForm } from '~/integrations/edit/store';
import SlackDuoAdminSection from 'ee/integrations/edit/components/slack_duo_admin_section.vue';
import SlackDuoSection from 'ee/integrations/edit/components/slack_duo_section.vue';
import { mockIntegrationProps } from 'jest/integrations/edit/mock_data';

Vue.use(PiniaVuePlugin);

describe('IntegrationForm with GitLab Duo for Slack', () => {
  let wrapper;

  const slackDuo = { scope: 'pointer', state: 'off' };

  const createComponent = (customStateProps = {}) => {
    const pinia = createTestingPinia({ stubActions: true });
    Object.assign(useIntegrationForm(), {
      customState: { ...mockIntegrationProps, ...customStateProps },
    });

    wrapper = shallowMountExtended(IntegrationForm, { pinia });
  };

  const findSection = () => wrapper.findComponent(SlackDuoSection);
  const findAdminSection = () => wrapper.findComponent(SlackDuoAdminSection);

  it('renders the GitLab Duo section on the Slack integration page', () => {
    createComponent({ type: INTEGRATION_FORM_TYPE_SLACK, slackDuo });

    expect(findSection().props('slackDuo')).toEqual({ scope: 'pointer', state: 'off' });
  });

  it('renders nothing without the data', () => {
    createComponent({ type: INTEGRATION_FORM_TYPE_SLACK });

    expect(findSection().exists()).toBe(false);
  });

  it('renders nothing on the page of another integration', () => {
    createComponent({ type: 'jira', slackDuo });

    expect(findSection().exists()).toBe(false);
  });

  describe('in the Admin area', () => {
    const slackDuoAdmin = { scope: 'admin', state: 'off' };

    it('renders the Admin area GitLab Duo section', () => {
      createComponent({ type: INTEGRATION_FORM_TYPE_SLACK, slackDuoAdmin });

      expect(findAdminSection().props('slackDuoAdmin')).toEqual({ scope: 'admin', state: 'off' });
      expect(findSection().exists()).toBe(false);
    });

    it('renders nothing on the page of another integration', () => {
      createComponent({ type: 'jira', slackDuoAdmin });

      expect(findAdminSection().exists()).toBe(false);
    });
  });
});
