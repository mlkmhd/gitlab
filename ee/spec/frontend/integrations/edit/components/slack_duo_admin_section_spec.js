import { GlCollapsibleListbox } from '@gitlab/ui';
import MockAdapter from 'axios-mock-adapter';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import axios from '~/lib/utils/axios_utils';
import { createAlert } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { getGroups } from '~/rest_api';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_action';
import {
  HTTP_STATUS_INTERNAL_SERVER_ERROR,
  HTTP_STATUS_OK,
  HTTP_STATUS_UNPROCESSABLE_ENTITY,
} from '~/lib/utils/http_status';
import SlackDuoAdminSection from 'ee/integrations/edit/components/slack_duo_admin_section.vue';
import SlackDuoPermissionsAlert from 'ee/integrations/edit/components/slack_duo_permissions_alert.vue';
import SlackDuoRequirements from 'ee/integrations/edit/components/slack_duo_requirements.vue';

jest.mock('~/alert');
jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('~/rest_api');
jest.mock('~/lib/utils/confirm_via_gl_modal/confirm_action');

const updatePath = '/admin/application_settings/slack/duo_group';

const acme = { id: 1, name: 'Acme', linkKind: 'settings', linkPath: '/groups/acme/-/settings' };

const adminData = (overrides = {}) => ({
  scope: 'admin',
  state: 'off',
  teamId: 'TINST',
  teamName: 'Instance workspace',
  duoGroup: null,
  slackPermissionsOk: true,
  reinstallPath: null,
  requirements: [],
  seatsRequired: false,
  groupSettingsPath: null,
  updatePath,
  instanceSettingsPath: '/admin/gitlab_duo/configuration',
  ...overrides,
});

// The PUT endpoint answers in snake_case, like the page data before the frontend converts it.
const adminResponse = (overrides = {}) => ({
  scope: 'admin',
  state: 'off',
  team_id: 'TINST',
  team_name: 'Instance workspace',
  duo_group: null,
  slack_permissions_ok: true,
  reinstall_path: null,
  requirements: [],
  seats_required: false,
  group_settings_path: null,
  update_path: updatePath,
  instance_settings_path: '/admin/gitlab_duo/configuration',
  ...overrides,
});

const apiGroups = [
  { id: 1, full_name: 'Acme', full_path: 'acme', avatar_url: null },
  { id: 2, full_name: 'Beta', full_path: 'beta', avatar_url: null },
];

describe('SlackDuoAdminSection', () => {
  let wrapper;
  let mock;
  const toast = { show: jest.fn() };

  const createComponent = (slackDuoAdmin = adminData()) => {
    wrapper = mountExtended(SlackDuoAdminSection, {
      propsData: { slackDuoAdmin },
      mocks: { $toast: toast },
    });
  };

  const findBadge = () => wrapper.findByTestId('slack-duo-admin-badge');
  const findPicker = () => wrapper.findComponent(GlCollapsibleListbox);
  const findTurnOff = () => wrapper.findComponentByTestId('slack-duo-admin-turn-off');
  const findRequirements = () => wrapper.findComponent(SlackDuoRequirements);

  const deferred = () => {
    const handle = {};
    handle.promise = new Promise((resolve, reject) => {
      handle.resolve = resolve;
      handle.reject = reject;
    });
    return handle;
  };

  const typeSearch = async (term) => {
    findPicker().vm.$emit('search', term);
    jest.runAllTimers();
    await waitForPromises();
  };

  const openPicker = async () => {
    findPicker().vm.$emit('shown');
    await waitForPromises();
  };

  beforeEach(() => {
    mock = new MockAdapter(axios);
    confirmAction.mockResolvedValue(true);
    getGroups.mockResolvedValue({ data: apiGroups, headers: {} });
  });

  afterEach(() => {
    mock.restore();
  });

  describe('without an instance install', () => {
    beforeEach(() => {
      createComponent({ scope: 'admin', state: 'not_connected', updatePath });
    });

    it('asks to install the app, with no picker and no badge', () => {
      expect(wrapper.findByTestId('slack-duo-admin-not-connected').text()).toBe(
        'Install the GitLab for Slack app to use GitLab Duo in Slack.',
      );
      expect(findPicker().exists()).toBe(false);
      expect(findBadge().exists()).toBe(false);
    });
  });

  describe('while GitLab Duo is off', () => {
    beforeEach(() => {
      createComponent();
    });

    it('names the workspace and offers the picker, without turn off or requirements', () => {
      expect(wrapper.findByTestId('slack-duo-admin-title-workspace').text()).toBe(
        'GitLab Duo for Instance workspace',
      );
      expect(wrapper.findByTestId('slack-duo-admin-help').text()).toContain(
        'Instance workspace is connected for the whole instance.',
      );
      expect(findBadge().text()).toBe('Off');
      expect(findPicker().props('toggleText')).toBe('Choose a top-level group');
      expect(findTurnOff().exists()).toBe(false);
      expect(findRequirements().exists()).toBe(false);
    });

    it('searches top-level groups when the picker opens and as the administrator types', async () => {
      await openPicker();

      expect(getGroups).toHaveBeenCalledWith('', {
        top_level_only: true,
        active: true,
        order_by: 'name',
      });
      expect(findPicker().props('items')).toEqual([
        { value: 1, text: 'Acme', fullPath: 'acme', avatarUrl: null },
        { value: 2, text: 'Beta', fullPath: 'beta', avatarUrl: null },
      ]);

      await typeSearch('be');

      expect(getGroups).toHaveBeenLastCalledWith('be', {
        top_level_only: true,
        active: true,
        order_by: 'name',
      });
    });

    it('keeps the answer to the latest term when an earlier one answers last', async () => {
      const first = deferred();
      const second = deferred();
      getGroups.mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);

      findPicker().vm.$emit('search', 'a');
      jest.runAllTimers();
      findPicker().vm.$emit('search', 'ab');
      jest.runAllTimers();

      second.resolve({ data: [apiGroups[0]], headers: {} });
      await waitForPromises();
      first.resolve({ data: apiGroups, headers: {} });
      await waitForPromises();

      expect(findPicker().props('items')).toEqual([
        { value: 1, text: 'Acme', fullPath: 'acme', avatarUrl: null },
      ]);
      expect(findPicker().props('searching')).toBe(false);
    });

    it('keeps searching while the latest term loads after an earlier one answers', async () => {
      const first = deferred();
      const second = deferred();
      getGroups.mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);

      findPicker().vm.$emit('search', 'a');
      jest.runAllTimers();
      findPicker().vm.$emit('search', 'ab');
      jest.runAllTimers();

      first.resolve({ data: apiGroups, headers: {} });
      await waitForPromises();

      expect(findPicker().props('searching')).toBe(true);
      expect(findPicker().props('items')).toEqual([]);

      second.resolve({ data: [apiGroups[0]], headers: {} });
      await waitForPromises();

      expect(findPicker().props('searching')).toBe(false);
    });

    it('searches the typed term again when the picker opens again', async () => {
      await openPicker();
      await typeSearch('acme');
      getGroups.mockClear();

      await openPicker();

      expect(getGroups).toHaveBeenCalledWith('acme', {
        top_level_only: true,
        active: true,
        order_by: 'name',
      });
    });

    it('says in the picker when the groups cannot load, and reports it', async () => {
      const error = new Error('boom');
      getGroups.mockRejectedValue(error);

      await openPicker();

      expect(findPicker().props('noResultsText')).toBe('Could not load groups. Try again.');
      expect(wrapper.findByTestId('listbox-no-results-text').text()).toBe(
        'Could not load groups. Try again.',
      );
      expect(findPicker().props('items')).toEqual([]);
      expect(Sentry.captureException).toHaveBeenCalledWith(error);
      expect(createAlert).not.toHaveBeenCalled();
    });

    it('ignores a failed search for an earlier term', async () => {
      const first = deferred();
      getGroups.mockReturnValueOnce(first.promise);

      findPicker().vm.$emit('search', 'a');
      jest.runAllTimers();
      await typeSearch('ab');
      first.reject(new Error('boom'));
      await waitForPromises();

      expect(findPicker().props('noResultsText')).toBe('No results found');
      expect(findPicker().props('items')).toHaveLength(2);
      expect(Sentry.captureException).not.toHaveBeenCalled();
    });

    it('runs GitLab Duo in the chosen group after confirming, and renders the answer', async () => {
      mock
        .onPut(updatePath, { team_id: 'TINST', group_id: 1 })
        .reply(HTTP_STATUS_OK, adminResponse({ state: 'on', duo_group: { id: 1, name: 'Acme' } }));
      await openPicker();

      findPicker().vm.$emit('select', 1);
      await waitForPromises();

      expect(confirmAction).toHaveBeenCalledWith(
        expect.stringContaining('Run GitLab Duo for Instance workspace in Acme?'),
        { primaryBtnText: 'Turn on GitLab Duo' },
      );
      expect(toast.show).toHaveBeenCalledWith('GitLab Duo in Slack updated.');
      expect(findBadge().text()).toBe('On');
      expect(findPicker().props('toggleText')).toBe('Acme');
      expect(findTurnOff().exists()).toBe(true);
    });

    it('sets the picker loading while the change saves', async () => {
      const pending = deferred();
      mock.onPut(updatePath).reply(() => pending.promise);
      await openPicker();

      findPicker().vm.$emit('select', 1);
      await waitForPromises();

      expect(findPicker().props('loading')).toBe(true);

      pending.resolve([HTTP_STATUS_OK, adminResponse()]);
      await waitForPromises();

      expect(findPicker().props('loading')).toBe(false);
    });

    it('changes nothing when the administrator cancels', async () => {
      confirmAction.mockResolvedValue(false);
      await openPicker();

      findPicker().vm.$emit('select', 1);
      await waitForPromises();

      expect(mock.history.put).toHaveLength(0);
    });

    it("shows the backend's reason when it refuses the group", async () => {
      mock
        .onPut(updatePath)
        .reply(HTTP_STATUS_UNPROCESSABLE_ENTITY, { message: 'Archived group', reason: 'x' });
      await openPicker();

      findPicker().vm.$emit('select', 2);
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith({ message: 'Archived group' });
      expect(findBadge().text()).toBe('Off');
    });

    it('shows a generic error and reports it when the request fails', async () => {
      mock.onPut(updatePath).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);
      await openPicker();

      findPicker().vm.$emit('select', 2);
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({
          message: 'Could not update GitLab Duo for Slack. Try again.',
          captureError: true,
        }),
      );
    });
  });

  describe('while GitLab Duo runs in a group', () => {
    const requirements = [{ id: 'duo_features', ok: true, fix: 'group_settings' }];

    beforeEach(() => {
      createComponent(
        adminData({
          state: 'on',
          duoGroup: acme,
          requirements,
          groupSettingsPath: '/groups/acme/-/settings/gitlab_duo',
        }),
      );
    });

    it('shows the group, the turn off button and the requirements', () => {
      expect(findBadge().text()).toBe('On');
      expect(findPicker().props('selected')).toBe(1);
      expect(findRequirements().props()).toEqual({
        requirements,
        groupSettingsPath: '/groups/acme/-/settings/gitlab_duo',
        instanceSettingsPath: '/admin/gitlab_duo/configuration',
        slackReady: true,
      });
    });

    it('asks to move GitLab Duo to another group', async () => {
      mock
        .onPut(updatePath)
        .reply(HTTP_STATUS_OK, adminResponse({ state: 'on', duo_group: { id: 2, name: 'Beta' } }));
      await openPicker();

      findPicker().vm.$emit('select', 2);
      await waitForPromises();

      expect(confirmAction).toHaveBeenCalledWith(
        expect.stringContaining('Move GitLab Duo from Acme to Beta?'),
        { primaryBtnText: 'Move GitLab Duo' },
      );
      expect(JSON.parse(mock.history.put[0].data)).toEqual({ team_id: 'TINST', group_id: 2 });
    });

    it('does nothing when the administrator picks the same group', async () => {
      await openPicker();

      findPicker().vm.$emit('select', 1);
      await waitForPromises();

      expect(confirmAction).not.toHaveBeenCalled();
    });

    it('turns GitLab Duo off after confirming', async () => {
      mock.onPut(updatePath).reply(HTTP_STATUS_OK, adminResponse());

      findTurnOff().vm.$emit('click');
      await waitForPromises();

      expect(confirmAction).toHaveBeenCalledWith(
        expect.stringContaining('Turn off GitLab Duo for Instance workspace?'),
        { primaryBtnText: 'Turn off GitLab Duo', primaryBtnVariant: 'danger' },
      );
      expect(JSON.parse(mock.history.put[0].data)).toEqual({ team_id: 'TINST', group_id: null });
      expect(toast.show).toHaveBeenCalledWith('GitLab Duo turned off for this Slack workspace.');
      expect(findBadge().text()).toBe('Off');
      expect(findTurnOff().exists()).toBe(false);
    });

    it('sets the picker and the turn off button loading while turning off', async () => {
      const pending = deferred();
      mock.onPut(updatePath).reply(() => pending.promise);

      findTurnOff().vm.$emit('click');
      await waitForPromises();

      expect(findPicker().props('loading')).toBe(true);
      expect(findTurnOff().props('loading')).toBe(true);

      pending.resolve([HTTP_STATUS_OK, adminResponse()]);
      await waitForPromises();

      expect(findPicker().props('loading')).toBe(false);
    });

    it('keeps GitLab Duo on when the administrator cancels turning it off', async () => {
      confirmAction.mockResolvedValue(false);

      findTurnOff().vm.$emit('click');
      await waitForPromises();

      expect(mock.history.put).toHaveLength(0);
    });
  });

  it('needs attention when a requirement fails', () => {
    createComponent(
      adminData({ state: 'on', duoGroup: acme, requirements: [{ id: 'duo_features', ok: false }] }),
    );

    expect(findBadge().text()).toBe('Needs attention');
  });

  describe('when the app cannot read mentions', () => {
    beforeEach(() => {
      createComponent(
        adminData({
          state: 'on',
          duoGroup: acme,
          slackPermissionsOk: false,
          reinstallPath: '/admin/application_settings/integrations/gitlab_slack_application/edit',
          requirements: [{ id: 'duo_features', ok: true, fix: 'group_settings' }],
        }),
      );
    });

    it('tells the requirements card that GitLab Duo cannot answer yet', () => {
      expect(findRequirements().props('slackReady')).toBe(false);
    });

    it('asks to reinstall the app, and needs attention', () => {
      expect(wrapper.findComponent(SlackDuoPermissionsAlert).props()).toEqual({
        teamName: 'Instance workspace',
        reinstallPath: '/admin/application_settings/integrations/gitlab_slack_application/edit',
      });
      expect(findBadge().text()).toBe('Needs attention');
    });
  });

  it('notes the seat requirement when GitLab Duo needs seats', () => {
    createComponent(adminData({ seatsRequired: true }));

    expect(wrapper.findByTestId('slack-duo-admin-help').text()).toContain(
      'Only members with active GitLab Duo seats can use @GitLab.',
    );
  });
});
