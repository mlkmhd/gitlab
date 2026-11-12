import { mountExtended } from 'helpers/vue_test_utils_helper';
import SlackDuoRequirements from 'ee/integrations/edit/components/slack_duo_requirements.vue';

describe('SlackDuoRequirements', () => {
  let wrapper;

  const createComponent = (props) => {
    wrapper = mountExtended(SlackDuoRequirements, {
      propsData: {
        groupSettingsPath: '/groups/acme/-/settings/gitlab_duo',
        instanceSettingsPath: null,
        ...props,
      },
    });
  };

  const findCheck = (id) => wrapper.findByTestId(`slack-duo-requirement-${id}`);

  it('says it is ready and hides the list until asked', async () => {
    createComponent({ requirements: [{ id: 'duo_features', ok: true, fix: 'group_settings' }] });

    expect(wrapper.text()).toContain('Ready. Members of the group can mention @GitLab in Slack.');
    expect(findCheck('duo_features').isVisible()).toBe(false);

    await wrapper.findByTestId('slack-duo-toggle-requirements').trigger('click');

    expect(findCheck('duo_features').isVisible()).toBe(true);
  });

  it('does not say it is ready while the Slack app needs reinstalling, and shows the list', () => {
    createComponent({
      requirements: [{ id: 'duo_features', ok: true, fix: 'group_settings' }],
      slackReady: false,
    });

    expect(wrapper.text()).not.toContain('Ready.');
    expect(wrapper.findByTestId('slack-duo-toggle-requirements').exists()).toBe(false);
    expect(findCheck('duo_features').isVisible()).toBe(true);
  });

  it('says what failed, and links it to the GitLab Duo settings with a name that says so', () => {
    createComponent({ requirements: [{ id: 'duo_features', ok: false, fix: 'group_settings' }] });

    const link = findCheck('duo_features').find('a');
    expect(wrapper.text()).toContain("GitLab Duo can't answer in Slack until these are fixed:");
    expect(findCheck('duo_features').text()).toContain('GitLab Duo is turned off');
    expect(findCheck('duo_features').text()).not.toContain('GitLab Duo is turned on');
    expect(link.attributes('href')).toBe('/groups/acme/-/settings/gitlab_duo');
    expect(link.attributes('aria-label')).toBe(
      'Open GitLab Duo settings to fix: GitLab Duo is turned off',
    );
  });

  it('keeps the passing wording for a check that passed', () => {
    createComponent({
      requirements: [
        { id: 'duo_features', ok: true, fix: 'group_settings' },
        { id: 'agent_platform', ok: false, fix: 'group_settings' },
      ],
    });

    expect(findCheck('duo_features').text()).toBe('GitLab Duo is turned on');
    expect(findCheck('agent_platform').text()).toContain('GitLab Duo Agent Platform is turned off');
  });

  it('asks a non-administrator to ask their administrator for an instance setting', () => {
    createComponent({
      requirements: [{ id: 'experiment_features', ok: false, fix: 'instance_settings' }],
    });

    expect(findCheck('experiment_features').text()).toContain(
      'Experiment and beta features are turned off',
    );
    expect(findCheck('experiment_features').text()).toContain(
      'Ask your administrator to change this.',
    );
    expect(findCheck('experiment_features').find('a').exists()).toBe(false);
  });
});
