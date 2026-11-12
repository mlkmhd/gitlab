import { GlToggle } from '@gitlab/ui';
import MockAdapter from 'axios-mock-adapter';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import axios from '~/lib/utils/axios_utils';
import { createAlert } from '~/alert';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_action';
import {
  HTTP_STATUS_INTERNAL_SERVER_ERROR,
  HTTP_STATUS_OK,
  HTTP_STATUS_UNPROCESSABLE_ENTITY,
} from '~/lib/utils/http_status';
import SlackDuoSection from 'ee/integrations/edit/components/slack_duo_section.vue';
import SlackDuoRequirements from 'ee/integrations/edit/components/slack_duo_requirements.vue';

jest.mock('~/alert');
jest.mock('~/lib/utils/confirm_via_gl_modal/confirm_action');

const path = '/groups/acme/-/settings/slack/duo_group';

const row = (teamId, overrides = {}) => ({
  teamId,
  teamName: `Workspace ${teamId}`,
  state: 'off',
  installedIn: [],
  duoGroup: null,
  canManage: true,
  slackPermissionsOk: true,
  ...overrides,
});

const groupData = (overrides = {}) => ({
  scope: 'group',
  state: 'workspaces',
  ownTeamId: 'TOWN',
  workspaces: [row('TOWN')],
  moreCount: 0,
  requirements: [],
  seatsRequired: false,
  updatePath: path,
  workspacesPath: path,
  adminIntegrationPath: null,
  ...overrides,
});

// A PUT that answers only when the test calls the returned function.
const holdPut = (mock, teamId) => {
  let answer;
  mock.onPut(path, { enabled: true, team_id: teamId }).reply(
    () =>
      new Promise((resolve) => {
        answer = () =>
          resolve([
            HTTP_STATUS_OK,
            { ...groupData(), updated_workspace: row(teamId, { state: 'on_here' }) },
          ]);
      }),
  );
  return () => answer();
};

describe('SlackDuoSection', () => {
  let wrapper;
  let mock;
  const toast = { show: jest.fn() };

  const createComponent = (slackDuo = groupData()) => {
    wrapper = mountExtended(SlackDuoSection, {
      propsData: { slackDuo },
      mocks: { $toast: toast },
    });
  };

  const findMain = () => wrapper.findByTestId('slack-duo-main');
  const findMainToggle = () => wrapper.findByTestId('slack-duo-toggle').findComponent(GlToggle);
  const findNotice = () => wrapper.findByTestId('slack-duo-notice');

  beforeEach(() => {
    mock = new MockAdapter(axios);
    confirmAction.mockResolvedValue(true);
  });

  afterEach(() => {
    mock.restore();
  });

  describe("the page's own workspace", () => {
    it('shows a toggle with the workspace name', () => {
      createComponent();

      expect(findMain().text()).toContain('GitLab Duo for Workspace TOWN');
      expect(findMainToggle().props('value')).toBe(false);
      expect(wrapper.findByTestId('slack-duo-toggle-help').text()).toContain(
        'Turn on to run all GitLab Duo sessions from Workspace TOWN in this group',
      );
    });

    it('labels the toggle with the workspace name as written', () => {
      createComponent(groupData({ workspaces: [row('TOWN', { teamName: 'Acme & Co' })] }));

      expect(findMainToggle().props('label')).toBe('GitLab Duo for Acme & Co');
    });

    it.each`
      seatsRequired | shown
      ${true}       | ${true}
      ${false}      | ${false}
    `(
      'shows the seat note: $shown when seatsRequired is $seatsRequired',
      ({ seatsRequired, shown }) => {
        createComponent(groupData({ seatsRequired }));

        expect(wrapper.findByTestId('slack-duo-seat-note').exists()).toBe(shown);
      },
    );

    it('turns GitLab Duo on and shows the answer of the server', async () => {
      mock.onPut(path, { enabled: true, team_id: 'TOWN' }).reply(HTTP_STATUS_OK, {
        ...groupData(),
        workspaces: [row('TOWN', { state: 'on_here' })],
        updated_workspace: row('TOWN', { state: 'on_here' }),
      });
      createComponent();

      findMainToggle().vm.$emit('change', true);
      await waitForPromises();

      expect(confirmAction).not.toHaveBeenCalled();
      expect(findMainToggle().props('value')).toBe(true);
      expect(wrapper.findByTestId('slack-duo-badge').text()).toBe('On');
      expect(toast.show).toHaveBeenCalledWith('GitLab Duo turned on for this Slack workspace.');
    });

    it.each`
      seatsRequired | describedBy
      ${false}      | ${['slack-duo-toggle-help']}
      ${true}       | ${['slack-duo-toggle-help', 'slack-duo-seat-note']}
    `(
      'describes the toggle with its help text when seatsRequired is $seatsRequired',
      ({ seatsRequired, describedBy }) => {
        createComponent(groupData({ seatsRequired }));

        expect(findMainToggle().props('ariaDescribedby').split(' ')).toEqual(
          describedBy.map((testId) => wrapper.findByTestId(testId).attributes('id')),
        );
      },
    );

    it('ignores another change while the save runs', async () => {
      const answer = holdPut(mock, 'TOWN');
      createComponent();

      findMainToggle().vm.$emit('change', true);
      await waitForPromises();
      findMainToggle().vm.$emit('change', true);
      answer();
      await waitForPromises();

      expect(mock.history.put).toHaveLength(1);
      expect(toast.show).toHaveBeenCalledTimes(1);
    });

    it('asks before turning GitLab Duo off, and does nothing when cancelled', async () => {
      confirmAction.mockResolvedValue(false);
      createComponent(groupData({ workspaces: [row('TOWN', { state: 'on_here' })] }));

      findMainToggle().vm.$emit('change', false);
      await waitForPromises();

      expect(confirmAction).toHaveBeenCalledWith(
        expect.stringContaining('Turn off GitLab Duo for Workspace TOWN?'),
        expect.objectContaining({ primaryBtnVariant: 'danger' }),
      );
      expect(mock.history.put).toHaveLength(0);
    });

    it('turns GitLab Duo off once confirmed', async () => {
      mock.onPut(path, { enabled: false, team_id: 'TOWN' }).reply(HTTP_STATUS_OK, {
        ...groupData(),
        updated_workspace: row('TOWN', { state: 'off' }),
      });
      createComponent(groupData({ workspaces: [row('TOWN', { state: 'on_here' })] }));

      findMainToggle().vm.$emit('change', false);
      await waitForPromises();

      expect(mock.history.put).toHaveLength(1);
      expect(findMainToggle().props('value')).toBe(false);
      expect(wrapper.findByTestId('slack-duo-badge').text()).toBe('Off');
      expect(toast.show).toHaveBeenCalledWith('GitLab Duo turned off for this Slack workspace.');
    });

    it('shows a generic error and reports it when the server gives no message', async () => {
      mock.onPut(path).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);
      createComponent();

      findMainToggle().vm.$emit('change', true);
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'Could not update GitLab Duo for Slack. Try again.',
        error: expect.any(Error),
        captureError: true,
      });
      expect(findMainToggle().props('value')).toBe(false);
    });

    it('shows the error message of the server', async () => {
      mock
        .onPut(path)
        .reply(HTTP_STATUS_UNPROCESSABLE_ENTITY, { message: 'Managed in another group.' });
      createComponent();

      findMainToggle().vm.$emit('change', true);
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith({ message: 'Managed in another group.' });
    });

    it('says the administrator decides for an instance workspace, with no toggle', () => {
      createComponent(
        groupData({
          workspaces: [
            row('TOWN', {
              state: 'instance_managed',
              canManage: false,
              installedIn: [{ kind: 'instance' }],
            }),
          ],
          adminIntegrationPath: '/admin/slack',
        }),
      );

      expect(wrapper.findByTestId('slack-duo-toggle').exists()).toBe(false);
      expect(findNotice().text()).toContain(
        "Workspace TOWN is connected for the whole instance. Your administrator decides where GitLab Duo runs for it, and hasn't chosen a group yet, so it's off.",
      );
      expect(wrapper.findByTestId('slack-duo-notice-link').attributes('href')).toBe('/admin/slack');
    });

    it('does not say GitLab Duo is off for an instance workspace that runs it in a group the viewer cannot see', () => {
      createComponent(
        groupData({
          workspaces: [
            row('TOWN', {
              state: 'instance_managed',
              canManage: false,
              duoGroup: null,
              duoOn: true,
              installedIn: [{ kind: 'instance' }],
            }),
          ],
        }),
      );

      expect(findNotice().text()).toBe(
        'Workspace TOWN is connected for the whole instance. Your administrator decides where GitLab Duo runs for it.',
      );
    });

    it('does not name a group the viewer cannot see', () => {
      createComponent(
        groupData({ workspaces: [row('TOWN', { state: 'elsewhere', canManage: false })] }),
      );

      expect(findNotice().text()).toBe(
        "Workspace TOWN runs GitLab Duo in another group. Its sessions use that group's settings and credits.",
      );
    });

    it('needs attention and shows the requirements card when a requirement fails', () => {
      const requirements = [{ id: 'duo_features', ok: false, fix: 'group_settings' }];
      createComponent(
        groupData({
          workspaces: [row('TOWN', { state: 'on_here' })],
          requirements,
          groupSettingsPath: '/groups/acme/-/settings/gitlab_duo/configuration',
          instanceSettingsPath: null,
        }),
      );

      expect(wrapper.findByTestId('slack-duo-badge').text()).toBe('Needs attention');
      expect(wrapper.findComponent(SlackDuoRequirements).props()).toEqual({
        requirements,
        groupSettingsPath: '/groups/acme/-/settings/gitlab_duo/configuration',
        instanceSettingsPath: null,
        slackReady: true,
      });
    });

    describe('when the Slack app cannot read mentions of @GitLab', () => {
      const missingPermission = (overrides = {}) =>
        groupData({
          workspaces: [
            row('TOWN', {
              state: 'on_here',
              slackPermissionsOk: false,
              reinstallPath: '/reinstall',
              ...overrides,
            }),
          ],
        });

      it('needs attention, even when GitLab Duo is on', () => {
        createComponent(missingPermission());

        expect(wrapper.findByTestId('slack-duo-badge').text()).toBe('Needs attention');
      });

      it('tells the requirements card that GitLab Duo cannot answer yet', () => {
        createComponent({
          ...missingPermission(),
          requirements: [{ id: 'duo_features', ok: true, fix: 'group_settings' }],
        });

        expect(wrapper.findComponent(SlackDuoRequirements).props('slackReady')).toBe(false);
      });

      it('warns with the reinstall as the action', () => {
        createComponent(missingPermission());

        const alert = wrapper.findByTestId('slack-duo-permissions');
        expect(alert.text()).toContain('Reinstall to use GitLab Duo in Slack');
        expect(alert.text()).toContain(
          'The Slack app for Workspace TOWN is missing a permission GitLab Duo needs (reading mentions of @GitLab).',
        );
        expect(alert.find('a').attributes('href')).toBe('/reinstall');
        expect(alert.find('a').text()).toBe('Reinstall GitLab for Slack app');
      });

      it('warns without an action for someone who cannot reinstall', () => {
        createComponent(missingPermission({ reinstallPath: null }));

        expect(wrapper.findByTestId('slack-duo-permissions').find('a').exists()).toBe(false);
      });

      it('does not warn when the app has the permission', () => {
        createComponent(groupData({ workspaces: [row('TOWN', { state: 'on_here' })] }));

        expect(wrapper.findByTestId('slack-duo-permissions').exists()).toBe(false);
        expect(wrapper.findByTestId('slack-duo-badge').text()).toBe('On');
      });
    });
  });

  describe('when the group has no Slack workspace of its own', () => {
    it('asks to install the app when only workspaces below it exist', () => {
      createComponent(groupData({ ownTeamId: null, workspaces: [row('T1')] }));

      expect(findMain().exists()).toBe(false);
      expect(findNotice().text()).toBe(
        'Install the GitLab for Slack app to use GitLab Duo in Slack.',
      );
    });

    it('asks to install the app when the group has no workspace at all', () => {
      createComponent(groupData({ ownTeamId: null, workspaces: [], state: 'not_connected' }));

      expect(findNotice().text()).toBe(
        'Install the GitLab for Slack app to use GitLab Duo in Slack.',
      );
    });
  });

  describe('on a subgroup or project page', () => {
    const pointer = (notice) => ({ scope: 'pointer', state: 'off', teamName: 'Acme Eng', notice });

    it('names the workspace and who can turn it on', () => {
      createComponent(
        pointer({
          key: 'off_ask_owner',
          groupName: 'acme',
          linkKind: 'owners',
          linkPath: '/acme/owners',
        }),
      );

      expect(findMain().text()).toBe('GitLab Duo for Acme Eng');
      expect(findNotice().text()).toContain(
        'GitLab Duo is off for Acme Eng. An Owner of acme can turn it on.',
      );
      expect(wrapper.findByTestId('slack-duo-notice-link').text()).toBe('View the Owners of acme');
    });

    it('uses the unnamed wording when the viewer cannot see the group', () => {
      createComponent(pointer({ key: 'off_ask_owner' }));

      expect(findNotice().text()).toBe(
        'GitLab Duo is off for Acme Eng. An Owner of the top-level group can turn it on.',
      );
    });

    it.each`
      groupName    | text
      ${'acme'}    | ${'GitLab Duo in Slack is turned on by installing the GitLab for Slack app on the top-level group. Ask an Owner of acme to install it for Acme Eng.'}
      ${undefined} | ${'GitLab Duo in Slack is turned on by installing the GitLab for Slack app on the top-level group. Ask an Owner of the top-level group to install it for Acme Eng.'}
    `(
      'asks to install the app on the top-level group when it has not (group $groupName)',
      ({ groupName, text }) => {
        createComponent(pointer({ key: 'off_install_on_top_level', groupName }));

        expect(findNotice().text()).toBe(text);
      },
    );
  });
});
