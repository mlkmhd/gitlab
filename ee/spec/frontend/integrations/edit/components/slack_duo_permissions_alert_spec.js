import { GlAlert } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import SlackDuoPermissionsAlert from 'ee/integrations/edit/components/slack_duo_permissions_alert.vue';

describe('SlackDuoPermissionsAlert', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = mountExtended(SlackDuoPermissionsAlert, {
      propsData: { teamName: 'Workspace TOWN', ...props },
    });
  };

  const findAlert = () => wrapper.findComponent(GlAlert);

  it('names the workspace and the missing permission', () => {
    createComponent();

    expect(findAlert().props('title')).toBe('Reinstall to use GitLab Duo in Slack');
    expect(findAlert().text()).toContain(
      'The Slack app for Workspace TOWN is missing a permission GitLab Duo needs (reading mentions of @GitLab).',
    );
  });

  it('offers the reinstall as the action', () => {
    createComponent({ reinstallPath: '/reinstall' });

    expect(findAlert().props()).toMatchObject({
      primaryButtonText: 'Reinstall GitLab for Slack app',
      primaryButtonLink: '/reinstall',
    });
  });

  it('offers no action without a reinstall path', () => {
    createComponent();

    expect(findAlert().props('primaryButtonText')).toBe('');
  });
});
