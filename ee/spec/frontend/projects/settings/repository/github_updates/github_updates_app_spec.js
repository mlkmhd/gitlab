import { GlBadge, GlLink, GlModal, GlTableLite } from '@gitlab/ui';
import MockAdapter from 'axios-mock-adapter';
import { nextTick } from 'vue';
import Visibility from 'visibilityjs';
import GithubUpdatesApp from 'ee/projects/settings/repository/github_updates/github_updates_app.vue';
import axios from '~/lib/utils/axios_utils';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import {
  HTTP_STATUS_ACCEPTED,
  HTTP_STATUS_CONFLICT,
  HTTP_STATUS_INTERNAL_SERVER_ERROR,
  HTTP_STATUS_OK,
  HTTP_STATUS_UNPROCESSABLE_ENTITY,
} from '~/lib/utils/http_status';
import statusResponse from 'test_fixtures/github_updates/status.json';
import updateNowResponse from 'test_fixtures/github_updates/update_now.json';
import { stubComponent } from 'helpers/stub_component';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';

jest.mock('visibilityjs');
jest.mock('~/sentry/sentry_browser_wrapper');

describe('GithubUpdatesApp', () => {
  let wrapper;
  let mock;

  const statusUrl = '/group/project/-/github_updates/status';
  const updateNowUrl = '/group/project/-/github_updates/update_now';
  const stopUrl = '/group/project/-/github_updates/stop';
  const projectFullPath = 'group/project';

  // Overrides only keys the real endpoint sends, so a key renamed in the presenter fails here.
  const withFixtureKeys = (fixture, overrides) => {
    Object.keys(overrides).forEach((key) => {
      if (!(key in fixture)) throw new Error(`The status fixture has no "${key}" key`);
    });
    return { ...fixture, ...overrides };
  };

  const buildStatus = ({
    state = 'provider_canonical',
    source = 'current',
    workItems,
    lfs = 'current',
    finalPassIncomplete = false,
  } = {}) => {
    const { data } = statusResponse;

    return withFixtureKeys(statusResponse, {
      state,
      final_pass_incomplete: finalPassIncomplete,
      data: {
        inventory: data.inventory,
        source: withFixtureKeys(data.source, { state: source }),
        ...(workItems && { work_items: withFixtureKeys(data.work_items, { state: workItems }) }),
        ...(lfs && { lfs: withFixtureKeys(data.lfs, { state: lfs }) }),
      },
    });
  };

  let initialStatus;
  const setStatus = (status = buildStatus({ workItems: 'current' })) => {
    initialStatus = status;
  };

  const createComponent = ({
    repositoryUrl = 'https://github.com/octo-org/example',
    stopUrl: stopUrlProp = stopUrl,
    updateNowUrl: updateNowUrlProp = updateNowUrl,
  } = {}) => {
    wrapper = mountExtended(GithubUpdatesApp, {
      propsData: {
        statusUrl,
        updateNowUrl: updateNowUrlProp,
        stopUrl: stopUrlProp,
        projectFullPath,
        repositoryName: 'octo-org/example',
        repositoryUrl,
        initialStatus,
      },
      stubs: { GlModal: stubComponent(GlModal) },
    });
  };

  const findOverallStatus = () => wrapper.findByTestId('overall-status');
  const findRows = () => wrapper.findAll('tbody tr');
  const findStopButton = () => wrapper.findComponentByTestId('stop-updates');
  const findStatusErrorAlert = () => wrapper.findComponentByTestId('status-error-alert');
  const findUpdateButton = () => wrapper.findComponentByTestId('update-now');
  const findNotice = () => wrapper.findComponentByTestId('notice');
  const findFinalPassIncompleteAlert = () =>
    wrapper.findComponentByTestId('final-pass-incomplete-alert');
  const findModal = () => wrapper.findComponent(GlModal);

  const openStopModal = () => findStopButton().vm.$emit('click');
  const confirmStop = async (typed = projectFullPath) => {
    openStopModal();
    await wrapper.findByTestId('confirm-danger-field').setValue(typed);
    findModal().vm.$emit('primary');
    await waitForPromises();
  };

  const pollHeaders = { 'poll-interval': '5000' };
  const statusRequests = () => mock.history.get.filter(({ url }) => url === statusUrl);
  const advancePoll = async () => {
    jest.runOnlyPendingTimers();
    await waitForPromises();
  };

  beforeEach(() => {
    mock = new MockAdapter(axios);
    Visibility.hidden.mockReturnValue(false);
  });

  afterEach(() => {
    mock.restore();
  });

  it('links the repository name to GitHub', () => {
    setStatus();
    createComponent();

    expect(wrapper.findByRole('link', { name: 'octo-org/example' }).attributes('href')).toBe(
      'https://github.com/octo-org/example',
    );
    expect(wrapper.findComponent(GlLink).props('showExternalIcon')).toBe(true);
  });

  describe('when the repository has no GitHub URL', () => {
    beforeEach(() => {
      setStatus();

      createComponent({ repositoryUrl: '' });
    });

    it('shows the repository name without a link', () => {
      expect(wrapper.findByRole('link', { name: 'octo-org/example' }).exists()).toBe(false);
      expect(wrapper.text()).toContain('octo-org/example');
    });
  });

  describe('when the status has loaded', () => {
    beforeEach(() => {
      setStatus(buildStatus({ source: 'degraded', workItems: 'running', lfs: 'pending' }));

      createComponent();
    });

    it('shows rows for repository content, issues and merge requests, and LFS objects, not inventory', () => {
      expect(findRows()).toHaveLength(3);
      expect(findRows().at(0).text()).toContain('Repository');
      expect(findRows().at(0).text()).toContain('Error');
      expect(findRows().at(1).text()).toContain('Issues and merge requests');
      expect(findRows().at(1).text()).toContain('Updating…');
      expect(findRows().at(2).text()).toContain('LFS objects');
      expect(findRows().at(2).text()).toContain('Update scheduled…');
    });

    it('stacks the columns on narrow screens, labelling each cell with its column', () => {
      expect(wrapper.findComponent(GlTableLite).classes()).toContain('b-table-stacked-md');
      expect(
        findRows()
          .at(0)
          .findAll('[data-label]')
          .wrappers.map((cell) => cell.attributes('data-label')),
      ).toEqual(['Data', 'Update status', 'Last successful update', 'Last update attempt']);
    });

    it('explains a row that needs attention and shows when it last updated', () => {
      expect(findRows().at(0).text()).toContain('GitLab could not update this data from GitHub.');
      expect(findRows().at(0).find('time').exists()).toBe(true);
      expect(findRows().at(1).text()).toContain('Never');
    });
  });

  it('shows the last successful update and the last update attempt in their own columns', () => {
    const status = buildStatus({ workItems: 'current' });
    status.data.source.last_updated_at = null;
    setStatus(status);
    createComponent();

    const cell = (label) => findRows().at(0).find(`[data-label="${label}"]`);

    expect(cell('Last successful update').text()).toBe('Never');
    expect(cell('Last update attempt').find('time').attributes('datetime')).toBe(
      '2026-08-25T15:05:00.000Z',
    );
  });

  it('explains that a delayed row waits for the GitHub rate limit to reset', () => {
    setStatus(buildStatus({ source: 'delayed', workItems: 'current' }));
    createComponent();

    expect(findRows().at(0).text()).toContain('Update delayed');
    expect(findRows().at(0).text()).toContain(
      "GitHub's rate limit was reached. GitLab tries again when the limit resets.",
    );
  });

  describe('when a data row has no known state', () => {
    it('shows the row as unavailable', () => {
      setStatus(buildStatus());
      createComponent();

      expect(findRows().at(1).text()).toContain('Status unavailable');
    });

    it('shows a missing LFS row as unavailable', () => {
      setStatus(buildStatus({ workItems: 'current', lfs: null }));
      createComponent();

      expect(findRows().at(2).text()).toContain('LFS objects');
      expect(findRows().at(2).text()).toContain('Status unavailable');
    });
  });

  describe('once updates have stopped', () => {
    it.each`
      source        | workItems
      ${'degraded'} | ${'pending'}
      ${'running'}  | ${'delayed'}
      ${'current'}  | ${'paused'}
      ${'degraded'} | ${'current'}
    `(
      'shows that updates stopped, not the stored $source and $workItems states',
      ({ source, workItems }) => {
        setStatus(buildStatus({ state: 'gitlab_canonical', source, workItems }));
        createComponent();

        expect(findRows()).toHaveLength(3);
        findRows().wrappers.forEach((row) => {
          expect(row.findComponent(GlBadge).text()).toBe('Updates stopped');
          expect(row.text()).not.toMatch(
            /Error|Updating|Update scheduled|Update delayed|Paused|Up to date|could not update|rate limit/,
          );
        });
      },
    );

    it('still shows when each data type last updated', () => {
      setStatus(
        buildStatus({ state: 'gitlab_canonical', source: 'degraded', workItems: 'pending' }),
      );
      createComponent();

      expect(findRows().at(0).find('time').exists()).toBe(true);
      expect(findRows().at(1).text()).toContain('Never');
    });
  });

  describe('while updates have not stopped', () => {
    it.each([
      'provisioning',
      'provider_canonical',
      'disconnected',
      'cutting_over',
      'cutover_failed',
    ])('keeps showing the stored data states while the overall state is %s', (state) => {
      setStatus(buildStatus({ state, source: 'degraded', workItems: 'pending' }));
      createComponent();

      expect(findRows().at(0).findComponent(GlBadge).text()).toBe('Error');
      expect(findRows().at(1).findComponent(GlBadge).text()).toBe('Update scheduled…');
    });
  });

  describe('the warning about a stop before the latest changes were imported', () => {
    it('explains that recent GitHub changes might be missing', () => {
      setStatus(
        buildStatus({
          state: 'gitlab_canonical',
          source: 'degraded',
          workItems: 'pending',
          finalPassIncomplete: true,
        }),
      );
      createComponent();

      expect(findFinalPassIncompleteAlert().props('variant')).toBe('warning');
      expect(findFinalPassIncompleteAlert().props('dismissible')).toBe(false);
      expect(findFinalPassIncompleteAlert().text()).toBe(
        'GitHub updates stopped before the latest GitHub changes were imported. Recent changes on GitHub might be missing.',
      );
      expect(findRows().at(0).findComponent(GlBadge).text()).toBe('Updates stopped');
    });

    it.each`
      description                         | status
      ${'after a stop with a final pass'} | ${buildStatus({ state: 'gitlab_canonical', workItems: 'current' })}
      ${'while updates are on'}           | ${buildStatus({ workItems: 'current' })}
      ${'while updates are stopping'}     | ${buildStatus({ state: 'cutting_over', workItems: 'pending' })}
      ${'for a status without the field'} | ${{ ...buildStatus({ state: 'gitlab_canonical', workItems: 'current' }), final_pass_incomplete: undefined }}
    `('is not shown $description', ({ status }) => {
      setStatus(status);
      createComponent();

      expect(findFinalPassIncompleteAlert().exists()).toBe(false);
    });
  });

  describe('the stop button', () => {
    it('is a danger button that says stopping is permanent and needs a new import to undo', () => {
      setStatus();
      createComponent();

      expect(findStopButton().props()).toMatchObject({ variant: 'danger', category: 'secondary' });
      expect(findStopButton().text()).toBe('Stop GitHub updates');
      expect(wrapper.findByTestId('stop-section').text()).toContain(
        'Stopping updates is permanent. To get updates from GitHub again, import the repository again.',
      );
    });

    it.each`
      state                   | disabled
      ${'provisioning'}       | ${true}
      ${'provider_canonical'} | ${false}
      ${'disconnected'}       | ${true}
      ${'cutting_over'}       | ${true}
      ${'cutover_failed'}     | ${false}
      ${'a_future_state'}     | ${true}
    `('is disabled: $disabled when the overall state is $state', ({ state, disabled }) => {
      setStatus(buildStatus({ state, workItems: 'current' }));
      createComponent();

      expect(findStopButton().props('disabled')).toBe(disabled);
    });

    it.each`
      state                   | loading
      ${'provider_canonical'} | ${false}
      ${'cutting_over'}       | ${true}
      ${'cutover_failed'}     | ${false}
    `('is loading: $loading when the overall state is $state', ({ state, loading }) => {
      setStatus(buildStatus({ state, workItems: 'current' }));
      createComponent();

      expect(findStopButton().props('loading')).toBe(loading);
    });

    it.each`
      description                       | stopUrlProp | shown
      ${'the user can stop updates'}    | ${stopUrl}  | ${true}
      ${'the user cannot stop updates'} | ${''}       | ${false}
    `('is shown: $shown when $description', ({ stopUrlProp, shown }) => {
      setStatus();
      createComponent({ stopUrl: stopUrlProp });

      expect(wrapper.findByTestId('stop-section').exists()).toBe(shown);
      expect(findModal().exists()).toBe(shown);
      expect(findUpdateButton().exists()).toBe(true);
    });

    it('is not shown once updates have stopped', () => {
      setStatus(buildStatus({ state: 'gitlab_canonical', workItems: 'current' }));
      createComponent();

      expect(findStopButton().exists()).toBe(false);
      expect(wrapper.findByTestId('status-help').text()).toBe(
        'Updates from GitHub are stopped. To get updates from GitHub again, import the repository again.',
      );
    });

    it.each`
      state                 | text
      ${'provisioning'}     | ${'Setting up GitHub updates…'}
      ${'disconnected'}     | ${'GitHub connection lost'}
      ${'cutting_over'}     | ${'Stopping GitHub updates…'}
      ${'cutover_failed'}   | ${'GitHub updates are still on'}
      ${'gitlab_canonical'} | ${'Updates stopped'}
      ${'a_future_state'}   | ${'GitHub updates need attention'}
    `('shows $text as the overall status for $state', ({ state, text }) => {
      setStatus(buildStatus({ state, workItems: 'current' }));
      createComponent();

      expect(findOverallStatus().text()).toBe(text);
    });
  });

  describe('Update now', () => {
    it.each`
      state                   | source        | workItems         | disabled
      ${'provider_canonical'} | ${'current'}  | ${'current'}      | ${false}
      ${'provider_canonical'} | ${'pending'}  | ${'current'}      | ${true}
      ${'provider_canonical'} | ${'current'}  | ${'running'}      | ${true}
      ${'provider_canonical'} | ${'delayed'}  | ${'current'}      | ${true}
      ${'provider_canonical'} | ${'current'}  | ${'degraded'}     | ${false}
      ${'provider_canonical'} | ${'degraded'} | ${'degraded'}     | ${false}
      ${'provider_canonical'} | ${'degraded'} | ${'running'}      | ${true}
      ${'provider_canonical'} | ${'paused'}   | ${'current'}      | ${true}
      ${'provider_canonical'} | ${'current'}  | ${'disconnected'} | ${true}
      ${'provider_canonical'} | ${'current'}  | ${undefined}      | ${true}
      ${'cutover_failed'}     | ${'current'}  | ${'current'}      | ${true}
      ${'disconnected'}       | ${'current'}  | ${'current'}      | ${true}
    `(
      'is disabled: $disabled in $state with source $source and work items $workItems',
      ({ state, source, workItems, disabled }) => {
        setStatus(buildStatus({ state, source, workItems }));
        createComponent();

        expect(findUpdateButton().props('disabled')).toBe(disabled);
      },
    );

    it.each`
      state                   | rendered
      ${'provider_canonical'} | ${true}
      ${'gitlab_canonical'}   | ${false}
    `('is rendered: $rendered in $state', ({ state, rendered }) => {
      setStatus(buildStatus({ state, workItems: 'current' }));
      createComponent();

      expect(findUpdateButton().exists()).toBe(rendered);
    });

    it('is not rendered when the user cannot update', () => {
      setStatus();
      createComponent({ updateNowUrl: '' });

      expect(findUpdateButton().exists()).toBe(false);
    });

    it('is shown at the top of the panel, not in the data or stop section', () => {
      setStatus();
      createComponent();

      expect(findUpdateButton().element.closest('section')).toBeNull();
    });

    describe('when clicked', () => {
      beforeEach(() => {
        setStatus();
        createComponent();
      });

      it('requests an update and shows the scheduled data', async () => {
        mock.onPost(updateNowUrl).reply(HTTP_STATUS_ACCEPTED, updateNowResponse);

        findUpdateButton().vm.$emit('click');
        await waitForPromises();

        expect(mock.history.post).toHaveLength(1);
        expect(findNotice().text()).toBe('Update scheduled.');
        expect(findNotice().props('variant')).toBe('info');
        expect(findRows().at(0).text()).toContain('Update scheduled…');
        expect(findUpdateButton().props('disabled')).toBe(true);
      });

      it('shows the button as loading while the request is in flight', async () => {
        mock.onPost(updateNowUrl).reply(() => new Promise(() => {}));

        findUpdateButton().vm.$emit('click');
        await waitForPromises();

        expect(findUpdateButton().props('loading')).toBe(true);
      });

      it('shows the message of an error response', async () => {
        mock.onPost(updateNowUrl).reply(HTTP_STATUS_UNPROCESSABLE_ENTITY, {
          error: 'github_updates_not_updatable',
          message: 'An update can only be requested while GitHub updates are on.',
        });

        findUpdateButton().vm.$emit('click');
        await waitForPromises();

        expect(findNotice().text()).toBe(
          'An update can only be requested while GitHub updates are on.',
        );
        expect(findNotice().props('variant')).toBe('danger');
        expect(findUpdateButton().props('loading')).toBe(false);
        expect(findUpdateButton().props('disabled')).toBe(false);
        expect(Sentry.captureException).not.toHaveBeenCalled();
      });

      it('hides the notice when it is dismissed', async () => {
        mock.onPost(updateNowUrl).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);

        findUpdateButton().vm.$emit('click');
        await waitForPromises();
        findNotice().vm.$emit('dismiss');
        await nextTick();

        expect(findNotice().exists()).toBe(false);
      });

      it('disables the stop button while the request is in flight', async () => {
        mock.onPost(updateNowUrl).reply(() => new Promise(() => {}));

        findUpdateButton().vm.$emit('click');
        await waitForPromises();

        expect(findStopButton().props('disabled')).toBe(true);
      });

      it('shows a generic error when the response has no message and reports it', async () => {
        mock.onPost(updateNowUrl).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);

        findUpdateButton().vm.$emit('click');
        await waitForPromises();

        expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));

        expect(findNotice().text()).toBe(
          "GitLab couldn't schedule an update from GitHub. Try again.",
        );
      });

      it('shows a generic error when the request gets no response and reports it', async () => {
        mock.onPost(updateNowUrl).networkError();

        findUpdateButton().vm.$emit('click');
        await waitForPromises();

        expect(Sentry.captureException).toHaveBeenCalledTimes(1);
        expect(findNotice().text()).toBe(
          "GitLab couldn't schedule an update from GitHub. Try again.",
        );
      });
    });
  });

  describe('the LFS row', () => {
    it.each`
      lfs               | source       | disabled
      ${'running'}      | ${'current'} | ${false}
      ${'pending'}      | ${'current'} | ${false}
      ${'degraded'}     | ${'current'} | ${false}
      ${'disconnected'} | ${'current'} | ${false}
      ${null}           | ${'current'} | ${false}
      ${'current'}      | ${'running'} | ${true}
      ${'degraded'}     | ${'running'} | ${true}
    `(
      'does not change Update now: disabled $disabled with LFS $lfs and source $source',
      ({ lfs, source, disabled }) => {
        setStatus(buildStatus({ source, workItems: 'current', lfs }));
        createComponent();

        expect(findUpdateButton().props('disabled')).toBe(disabled);
      },
    );

    it('shows an LFS error in its row', () => {
      setStatus(buildStatus({ workItems: 'current', lfs: 'degraded' }));
      createComponent();

      expect(findRows().at(2).findComponent(GlBadge).text()).toBe('Error');
      expect(findRows().at(2).text()).toContain('GitLab could not update this data from GitHub.');
    });
  });

  describe('when a data row shows an error', () => {
    it('retries it with Update now', async () => {
      mock.onPost(updateNowUrl).reply(HTTP_STATUS_ACCEPTED, {
        ...buildStatus({ workItems: 'pending' }),
        message: updateNowResponse.message,
      });
      setStatus(buildStatus({ workItems: 'degraded' }));
      createComponent();

      expect(findRows().at(1).text()).toContain('Error');

      findUpdateButton().vm.$emit('click');
      await waitForPromises();

      expect(mock.history.post).toHaveLength(1);
      expect(findRows().at(1).text()).toContain('Update scheduled…');
    });
  });

  describe('stopping updates', () => {
    beforeEach(() => {
      setStatus();
      createComponent();
    });

    it('does not open the confirmation until the stop button is clicked', () => {
      expect(findModal().props('visible')).toBe(false);
    });

    it('opens the confirmation to type the project path, without calling the endpoint', async () => {
      openStopModal();
      await waitForPromises();

      expect(findModal().props('visible')).toBe(true);
      expect(findModal().text()).toContain('Enter the following to confirm: group/project');
      expect(findModal().text()).toContain(
        'A GitHub change made while the final check is running might not be included.',
      );
      expect(mock.history.post).toHaveLength(0);
    });

    it('closes the confirmation on cancel without calling the endpoint and keeps updates on', async () => {
      openStopModal();
      await waitForPromises();

      findModal().vm.$emit('change', false);
      await waitForPromises();

      expect(findModal().props('visible')).toBe(false);
      expect(findStopButton().exists()).toBe(true);
      expect(mock.history.post).toHaveLength(0);
    });

    it('keeps the stop button disabled and calls nothing until the typed text matches', async () => {
      openStopModal();
      await wrapper.findByTestId('confirm-danger-field').setValue('group/proj');

      expect(findModal().props('actionPrimary').attributes.disabled).toBe(true);
      expect(findModal().props('actionPrimary').text).toBe('Stop updates');
      expect(mock.history.post).toHaveLength(0);

      await wrapper.findByTestId('confirm-danger-field').setValue('group/project');

      expect(findModal().props('actionPrimary').attributes.disabled).toBe(false);
    });

    describe('when the path is confirmed', () => {
      it('stops updates and shows the resulting state', async () => {
        mock.onPost(stopUrl).reply(HTTP_STATUS_ACCEPTED, {
          ...buildStatus({ state: 'cutting_over', workItems: 'current' }),
          application_generation: 3,
        });

        await confirmStop();

        expect(mock.history.post).toHaveLength(1);
        expect(findOverallStatus().text()).toBe('Stopping GitHub updates…');
        expect(findStopButton().props('disabled')).toBe(true);
        expect(findNotice().exists()).toBe(false);
        expect(findModal().props('visible')).toBe(false);
      });

      it('disables the stop button and Update now while the stop is in flight', async () => {
        mock.onPost(stopUrl).reply(() => new Promise(() => {}));

        await confirmStop();

        expect(findStopButton().props('disabled')).toBe(true);
        expect(findStopButton().props('loading')).toBe(true);
        expect(findUpdateButton().props('disabled')).toBe(true);
      });

      it.each`
        status                              | message
        ${HTTP_STATUS_UNPROCESSABLE_ENTITY} | ${'GitLab must check GitHub for the latest changes before this project can be made editable.'}
        ${HTTP_STATUS_CONFLICT}             | ${'GitHub updates are still finishing. Try stopping updates again.'}
      `('shows the message of a $status error and stays read-only', async ({ status, message }) => {
        mock.onPost(stopUrl).reply(status, { message });

        await confirmStop();

        expect(findNotice().text()).toBe(message);
        expect(findOverallStatus().text()).toBe('GitHub updates are on');
        expect(findModal().props('visible')).toBe(false);
        expect(findStopButton().props('disabled')).toBe(false);
        expect(findStopButton().props('loading')).toBe(false);
        expect(Sentry.captureException).not.toHaveBeenCalled();
      });

      it('clears the previous error when the stop button is clicked again', async () => {
        mock.onPost(stopUrl).reply(HTTP_STATUS_CONFLICT, { message: 'Busy' });
        await confirmStop();

        openStopModal();
        await nextTick();

        expect(findNotice().exists()).toBe(false);
      });

      it('shows a generic error when the response has no message and reports it', async () => {
        mock.onPost(stopUrl).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);

        await confirmStop();

        expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));

        expect(findNotice().text()).toBe(
          'GitLab could not start the final check. This project is still read-only. Try again.',
        );
      });

      it('shows a generic error when the request gets no response and reports it', async () => {
        mock.onPost(stopUrl).networkError();

        await confirmStop();

        expect(Sentry.captureException).toHaveBeenCalledTimes(1);
        expect(findNotice().text()).toBe(
          'GitLab could not start the final check. This project is still read-only. Try again.',
        );
      });
    });
  });

  describe('polling', () => {
    it('does not poll a settled status', async () => {
      setStatus();
      createComponent();

      await advancePoll();

      expect(statusRequests()).toHaveLength(0);
    });

    it.each`
      state                 | workItems
      ${'disconnected'}     | ${'running'}
      ${'gitlab_canonical'} | ${'pending'}
    `(
      'does not poll a $state project whose data type was left $workItems',
      async ({ state, workItems }) => {
        setStatus(buildStatus({ state, workItems }));
        createComponent();

        await advancePoll();

        expect(statusRequests()).toHaveLength(0);
      },
    );

    it.each`
      description                       | status
      ${'while setup runs'}             | ${buildStatus({ state: 'provisioning', workItems: 'current' })}
      ${'while a data type is queued'}  | ${buildStatus({ source: 'pending', workItems: 'current' })}
      ${'while a data type updates'}    | ${buildStatus({ workItems: 'running' })}
      ${'while LFS objects update'}     | ${buildStatus({ workItems: 'current', lfs: 'running' })}
      ${'while a data type is delayed'} | ${buildStatus({ workItems: 'delayed' })}
      ${'while updates are stopping'}   | ${buildStatus({ state: 'cutting_over', workItems: 'current' })}
    `('polls $description and stops once the status settles', async ({ status }) => {
      mock
        .onGet(statusUrl)
        .reply(HTTP_STATUS_OK, buildStatus({ workItems: 'current' }), pollHeaders);
      setStatus(status);
      createComponent();

      await advancePoll();
      await advancePoll();

      expect(statusRequests()).toHaveLength(1);
      expect(findRows().at(1).text()).toContain('Up to date');
    });

    describe('when updates stop', () => {
      it('says to refresh the page once the stop finishes', async () => {
        mock
          .onGet(statusUrl)
          .reply(HTTP_STATUS_OK, buildStatus({ state: 'gitlab_canonical', workItems: 'current' }));
        setStatus(buildStatus({ state: 'cutting_over', workItems: 'current' }));
        createComponent();

        expect(findNotice().exists()).toBe(false);

        await advancePoll();

        expect(findNotice().props('variant')).toBe('success');
        expect(findNotice().text()).toBe(
          'GitHub updates stopped. Refresh the page to make changes in GitLab.',
        );
      });

      it('does not say so when the page loads with updates already stopped', () => {
        setStatus(buildStatus({ state: 'gitlab_canonical', workItems: 'current' }));
        createComponent();

        expect(findNotice().exists()).toBe(false);
      });
    });

    it('keeps polling on the Poll-Interval header while the status is in progress', async () => {
      mock
        .onGet(statusUrl)
        .replyOnce(HTTP_STATUS_OK, buildStatus({ workItems: 'running' }), pollHeaders)
        .onGet(statusUrl)
        .replyOnce(HTTP_STATUS_OK, buildStatus({ workItems: 'current' }), pollHeaders);
      setStatus(buildStatus({ workItems: 'running' }));
      createComponent();

      await advancePoll();
      await advancePoll();
      await advancePoll();

      expect(statusRequests()).toHaveLength(2);
      expect(findUpdateButton().props('disabled')).toBe(false);
    });

    it('starts polling after Update now so the panel follows the update', async () => {
      mock.onPost(updateNowUrl).reply(HTTP_STATUS_ACCEPTED, updateNowResponse);
      mock
        .onGet(statusUrl)
        .reply(HTTP_STATUS_OK, buildStatus({ workItems: 'current' }), pollHeaders);
      setStatus();
      createComponent();

      findUpdateButton().vm.$emit('click');
      await waitForPromises();
      await advancePoll();

      expect(statusRequests()).toHaveLength(1);
      expect(findRows().at(0).text()).toContain('Up to date');
    });

    it('ignores a poll that was sent before an action finished', async () => {
      let resolvePoll;
      mock.onGet(statusUrl).replyOnce(
        () =>
          new Promise((resolve) => {
            resolvePoll = () =>
              resolve([HTTP_STATUS_OK, buildStatus({ workItems: 'running' }), pollHeaders]);
          }),
      );
      mock.onPost(stopUrl).reply(HTTP_STATUS_ACCEPTED, buildStatus({ state: 'cutting_over' }));
      setStatus(buildStatus({ workItems: 'running' }));
      createComponent();

      await advancePoll();
      await confirmStop();
      resolvePoll();
      await waitForPromises();

      expect(findOverallStatus().text()).toBe('Stopping GitHub updates…');
    });

    it('retries a failed poll once and carries on when the retry succeeds', async () => {
      mock
        .onGet(statusUrl)
        .replyOnce(HTTP_STATUS_INTERNAL_SERVER_ERROR)
        .onGet(statusUrl)
        .replyOnce(HTTP_STATUS_OK, buildStatus({ workItems: 'current' }), pollHeaders);
      setStatus(buildStatus({ workItems: 'running' }));
      createComponent();

      await advancePoll();
      await advancePoll();

      expect(statusRequests()).toHaveLength(2);
      expect(findRows().at(1).text()).toContain('Up to date');
      expect(findStatusErrorAlert().exists()).toBe(false);
      expect(Sentry.captureException).not.toHaveBeenCalled();
    });

    it('retries a later failed poll again after a successful one', async () => {
      mock
        .onGet(statusUrl)
        .replyOnce(HTTP_STATUS_INTERNAL_SERVER_ERROR)
        .onGet(statusUrl)
        .replyOnce(HTTP_STATUS_OK, buildStatus({ workItems: 'running' }), pollHeaders)
        .onGet(statusUrl)
        .replyOnce(HTTP_STATUS_INTERNAL_SERVER_ERROR)
        .onGet(statusUrl)
        .replyOnce(HTTP_STATUS_OK, buildStatus({ workItems: 'current' }), pollHeaders);
      setStatus(buildStatus({ workItems: 'running' }));
      createComponent();

      await advancePoll();
      await advancePoll();
      await advancePoll();
      await advancePoll();

      expect(statusRequests()).toHaveLength(4);
      expect(findRows().at(1).text()).toContain('Up to date');
      expect(findStatusErrorAlert().exists()).toBe(false);
      expect(Sentry.captureException).not.toHaveBeenCalled();
    });

    it('does not start polling again when a poll finishes after the component is destroyed', async () => {
      let resolvePoll;
      mock.onGet(statusUrl).replyOnce(
        () =>
          new Promise((resolve) => {
            resolvePoll = () =>
              resolve([HTTP_STATUS_OK, buildStatus({ workItems: 'running' }), pollHeaders]);
          }),
      );
      setStatus(buildStatus({ workItems: 'running' }));
      createComponent();

      await advancePoll();
      wrapper.destroy();
      resolvePoll();
      await advancePoll();

      expect(statusRequests()).toHaveLength(1);
      expect(jest.getTimerCount()).toBe(0);
    });

    describe('when the retry fails too', () => {
      beforeEach(async () => {
        mock
          .onGet(statusUrl)
          .replyOnce(HTTP_STATUS_INTERNAL_SERVER_ERROR)
          .onGet(statusUrl)
          .replyOnce(HTTP_STATUS_INTERNAL_SERVER_ERROR)
          .onGet(statusUrl)
          .replyOnce(HTTP_STATUS_OK, buildStatus({ workItems: 'current' }), pollHeaders);
        setStatus(buildStatus({ state: 'cutover_failed', workItems: 'running' }));
        createComponent();

        await advancePoll();
        await advancePoll();
        await advancePoll();
      });

      it('stops polling, shows an error and reports it, and keeps the controls usable', () => {
        expect(statusRequests()).toHaveLength(2);
        expect(findStatusErrorAlert().props('variant')).toBe('danger');
        expect(findStatusErrorAlert().text()).toBe(
          "Couldn't load the GitHub updates status. Refresh the page to try again.",
        );
        expect(Sentry.captureException).toHaveBeenCalledTimes(1);
        expect(findStopButton().props()).toMatchObject({ disabled: false, loading: false });
      });

      it('hides the error when it is dismissed', async () => {
        findStatusErrorAlert().vm.$emit('dismiss');
        await nextTick();

        expect(findStatusErrorAlert().exists()).toBe(false);
      });

      it('starts again on the next tab change and clears the error', async () => {
        Visibility.change.mock.calls[0][0]();
        await advancePoll();

        expect(statusRequests()).toHaveLength(3);
        expect(findRows().at(1).text()).toContain('Up to date');
        expect(findStatusErrorAlert().exists()).toBe(false);
      });

      it('clears the error when updates are stopped', async () => {
        mock
          .onPost(stopUrl)
          .reply(
            HTTP_STATUS_ACCEPTED,
            buildStatus({ state: 'cutting_over', workItems: 'current' }),
          );

        await confirmStop();

        expect(findStatusErrorAlert().exists()).toBe(false);
      });
    });

    it.each`
      description                     | stopPolling
      ${'the tab is hidden'}          | ${() => Visibility.change.mock.calls[0][0]()}
      ${'the component is destroyed'} | ${() => wrapper.destroy()}
    `('does not retry a failed poll once $description', async ({ stopPolling }) => {
      let rejectPoll;
      mock.onGet(statusUrl).replyOnce(
        () =>
          new Promise((resolve) => {
            rejectPoll = () => resolve([HTTP_STATUS_INTERNAL_SERVER_ERROR]);
          }),
      );
      setStatus(buildStatus({ workItems: 'running' }));
      createComponent();

      await advancePoll();
      Visibility.hidden.mockReturnValue(true);
      stopPolling();
      rejectPoll();
      await advancePoll();

      expect(statusRequests()).toHaveLength(1);
      expect(jest.getTimerCount()).toBe(0);
      expect(Sentry.captureException).not.toHaveBeenCalled();
    });

    describe('when the status stops changing', () => {
      const unchanged = buildStatus({ workItems: 'pending' });
      let now;

      beforeEach(() => {
        now = 0;
        jest.spyOn(Date, 'now').mockImplementation(() => now);
        mock.onGet(statusUrl).reply(HTTP_STATUS_OK, unchanged, pollHeaders);
        setStatus(unchanged);
        createComponent();
      });

      const pollAfter = async (ms) => {
        now += ms;
        await advancePoll();
      };

      it('keeps polling for up to five minutes, then stops', async () => {
        await pollAfter(4 * 60 * 1000);
        await pollAfter(60 * 1000 - 1);

        expect(statusRequests()).toHaveLength(2);

        await pollAfter(1);
        await pollAfter(5000);

        expect(statusRequests()).toHaveLength(3);
      });

      it('says the status might be out of date once polling stops, until it starts again', async () => {
        const findStaleAlert = () => wrapper.findComponentByTestId('status-stale-alert');

        await pollAfter(4 * 60 * 1000);

        expect(findStaleAlert().exists()).toBe(false);

        await pollAfter(60 * 1000);

        expect(findStaleAlert().props('variant')).toBe('info');
        expect(findStaleAlert().text()).toBe(
          'This status might be out of date. Refresh the page to update it.',
        );

        Visibility.change.mock.calls[0][0]();
        await nextTick();

        expect(findStaleAlert().exists()).toBe(false);
      });

      it('counts the five minutes from the last change', async () => {
        mock.reset();
        mock
          .onGet(statusUrl)
          .reply(HTTP_STATUS_OK, buildStatus({ workItems: 'running' }), pollHeaders);

        await pollAfter(4 * 60 * 1000);
        await pollAfter(4 * 60 * 1000);
        await pollAfter(5000);

        expect(statusRequests()).toHaveLength(3);
      });

      describe('once polling has stopped', () => {
        beforeEach(async () => {
          await pollAfter(5 * 60 * 1000);
          await pollAfter(5000);
        });

        it('starts again after a tab change', async () => {
          expect(statusRequests()).toHaveLength(1);

          Visibility.change.mock.calls[0][0]();
          await pollAfter(5000);

          expect(statusRequests()).toHaveLength(2);
        });

        it('starts again after a stop', async () => {
          expect(statusRequests()).toHaveLength(1);

          mock.onPost(stopUrl).reply(HTTP_STATUS_ACCEPTED, unchanged);
          await confirmStop();
          await pollAfter(5000);

          expect(statusRequests()).toHaveLength(2);
        });
      });
    });

    describe('when the tab is hidden', () => {
      beforeEach(() => {
        Visibility.hidden.mockReturnValue(true);
        setStatus(buildStatus({ workItems: 'running' }));
        createComponent();
      });

      it('waits for the tab to be shown before it polls', async () => {
        mock.onGet(statusUrl).reply(HTTP_STATUS_OK, buildStatus({ workItems: 'current' }));

        await advancePoll();

        expect(statusRequests()).toHaveLength(0);

        Visibility.hidden.mockReturnValue(false);
        Visibility.change.mock.calls[0][0]();
        await advancePoll();

        expect(statusRequests()).toHaveLength(1);
      });
    });

    it('stops polling when the component is destroyed', () => {
      Visibility.change.mockReturnValue(42);
      setStatus(buildStatus({ workItems: 'running' }));
      createComponent();

      wrapper.destroy();

      expect(Visibility.unbind).toHaveBeenCalledWith(42);
      expect(jest.getTimerCount()).toBe(0);
    });
  });
});
