import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlLink, GlSprintf } from '@gitlab/ui';
import MockAdapter from 'axios-mock-adapter';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import CommitListMirrorStatus from 'ee/projects/commits/components/commit_list_mirror_status.vue';
import divergedFromUpstreamQuery from 'ee/projects/commits/graphql/queries/diverged_from_upstream.query.graphql';
import { createAlert } from '~/alert';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_INTERNAL_SERVER_ERROR, HTTP_STATUS_OK } from '~/lib/utils/http_status';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';

Vue.use(VueApollo);

jest.mock('~/alert');
jest.mock('~/sentry/sentry_browser_wrapper');

describe('CommitListMirrorStatus', () => {
  let wrapper;
  let mock;

  const syncUrl = '/api/v4/projects/7/mirror/pull';

  const defaultPullMirror = {
    url: 'https://example.com/upstream.git',
    updateStatus: 'success',
    lastUpdateAt: '2026-11-01T10:00:00Z',
    lastSuccessfulUpdateAt: '2026-11-01T09:00:00Z',
    everUpdatedSuccessfully: true,
    hardFailed: false,
    updateScheduled: false,
    updating: false,
    canUpdate: true,
    settingsPath: '/group/project/-/mirror',
  };

  const divergedResponse = (diverged) => ({
    data: {
      project: {
        id: 'gid://gitlab/Project/7',
        repository: { divergedFromUpstream: diverged },
      },
    },
  });

  const divergedHandler = jest.fn();

  const createComponent = ({ pullMirror = {}, props = {} } = {}) => {
    wrapper = shallowMountExtended(CommitListMirrorStatus, {
      apolloProvider: createMockApollo([[divergedFromUpstreamQuery, divergedHandler]]),
      provide: {
        projectFullPath: 'group/project',
        projectId: '7',
        pullMirror: { ...defaultPullMirror, ...pullMirror },
      },
      propsData: {
        currentRef: 'main',
        currentRefType: 'heads',
        ...props,
      },
      stubs: { GlSprintf },
    });
  };

  const findUpstreamLink = () => wrapper.findComponent(GlLink);
  const findUpdateStatus = () => wrapper.findByTestId('mirror-update-status');
  const findHardFailed = () => wrapper.findByTestId('mirror-hard-failed');
  const findLastSuccessfulUpdate = () => wrapper.findByTestId('mirror-last-successful-update');
  const findDivergedWarning = () => wrapper.findByTestId('diverged-warning');
  const findUpdateButton = () => wrapper.findComponentByTestId('update-now-button');

  beforeEach(() => {
    window.gon = { api_version: 'v4', relative_url_root: '' };
    mock = new MockAdapter(axios);
    divergedHandler.mockResolvedValue(divergedResponse(false));
  });

  afterEach(() => {
    mock.restore();
  });

  it('links to the upstream repository', () => {
    createComponent();

    expect(findUpstreamLink().attributes('href')).toBe('https://example.com/upstream.git');
    expect(wrapper.text()).toContain(
      'This project is mirrored from https://example.com/upstream.git.',
    );
  });

  describe('update status', () => {
    describe('when the last update succeeded', () => {
      beforeEach(() => {
        createComponent();
      });

      it('shows when the mirror last updated', () => {
        expect(findUpdateStatus().text()).toBe('Pull mirroring updated .');
        expect(findUpdateStatus().findComponent(TimeAgoTooltip).props('time')).toBe(
          '2026-11-01T09:00:00Z',
        );
      });
    });

    describe('when the repository is read-only', () => {
      beforeEach(() => {
        createComponent({ pullMirror: { updateStatus: 'read_only' } });
      });

      it('shows that mirroring is disabled', () => {
        expect(findUpdateStatus().text()).toBe(
          'Pull mirroring is disabled because the repository is set to read-only.',
        );
      });
    });

    describe('when the mirror has never updated', () => {
      beforeEach(() => {
        createComponent({ pullMirror: { updateStatus: null } });
      });

      it('shows no status', () => {
        expect(findUpdateStatus().exists()).toBe(false);
      });
    });

    describe('when the last update failed', () => {
      describe('when the user can update the mirror', () => {
        beforeEach(() => {
          createComponent({ pullMirror: { updateStatus: 'failed' } });
        });

        it('links the failure to the mirror settings', () => {
          const settingsLink = findUpdateStatus().findComponent(GlLink);

          expect(settingsLink.attributes('href')).toBe('/group/project/-/mirror');
          expect(settingsLink.findComponent(TimeAgoTooltip).props('time')).toBe(
            '2026-11-01T10:00:00Z',
          );
        });

        it('shows when the mirror last updated successfully', () => {
          expect(findLastSuccessfulUpdate().findComponent(TimeAgoTooltip).props('time')).toBe(
            '2026-11-01T09:00:00Z',
          );
        });
      });

      describe('when the user cannot update the mirror', () => {
        beforeEach(() => {
          createComponent({ pullMirror: { updateStatus: 'failed', canUpdate: false } });
        });

        it('shows the failure without a link', () => {
          expect(findUpdateStatus().text()).toBe('Pull mirroring failed .');
          expect(findUpdateStatus().findComponent(GlLink).exists()).toBe(false);
        });
      });

      describe('when mirroring is paused after too many failures', () => {
        beforeEach(() => {
          createComponent({ pullMirror: { updateStatus: 'failed', hardFailed: true } });
        });

        it('explains that mirroring is paused', () => {
          expect(findHardFailed().text()).toContain(
            'Repository mirroring has been paused due to too many failed attempts.',
          );
        });
      });
    });
  });

  describe('Update now button', () => {
    it.each`
      pullMirror                       | text                   | disabled
      ${{}}                            | ${'Update now'}        | ${false}
      ${{ canUpdate: false }}          | ${'Update now'}        | ${true}
      ${{ updateScheduled: true }}     | ${'Update scheduled…'} | ${true}
      ${{ updating: true }}            | ${'Updating…'}         | ${true}
      ${{ updateStatus: 'read_only' }} | ${'Update now'}        | ${true}
    `('shows "$text" with disabled $disabled for $pullMirror', ({ pullMirror, text, disabled }) => {
      createComponent({ pullMirror });

      expect(findUpdateButton().text()).toBe(text);
      expect(findUpdateButton().props('disabled')).toBe(disabled);
    });

    describe('when the update succeeds', () => {
      beforeEach(() => {
        mock.onPost(syncUrl).replyOnce(HTTP_STATUS_OK);
        createComponent();
        findUpdateButton().vm.$emit('click');
      });

      it('shows the update as scheduled straight away', async () => {
        await nextTick();

        expect(findUpdateButton().text()).toBe('Update scheduled…');
      });

      it('starts a forced mirror update', async () => {
        await waitForPromises();

        expect(JSON.parse(mock.history.post[0].data)).toEqual({ force: true });
        expect(findUpdateButton().text()).toBe('Update scheduled…');
        expect(createAlert).not.toHaveBeenCalled();
      });
    });

    describe('when the update fails', () => {
      beforeEach(async () => {
        mock.onPost(syncUrl).replyOnce(HTTP_STATUS_INTERNAL_SERVER_ERROR);
        createComponent();
        findUpdateButton().vm.$emit('click');
        await waitForPromises();
      });

      it('shows an alert', () => {
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({ message: 'Failed to sync mirror.' }),
        );
      });

      it('enables the button again', () => {
        expect(findUpdateButton().text()).toBe('Update now');
        expect(findUpdateButton().props('disabled')).toBe(false);
      });
    });
  });

  describe('diverged warning', () => {
    it('asks whether the current branch has diverged', async () => {
      createComponent();
      await waitForPromises();

      expect(divergedHandler).toHaveBeenCalledWith({ projectPath: 'group/project', ref: 'main' });
    });

    describe('when the branch has diverged', () => {
      beforeEach(async () => {
        divergedHandler.mockResolvedValue(divergedResponse(true));
        createComponent();
        await waitForPromises();
      });

      it('shows the warning', () => {
        expect(findDivergedWarning().text()).toContain('This branch has diverged from upstream.');
        expect(findDivergedWarning().text()).toContain(
          'The branch could not be updated automatically because it has diverged from its upstream counterpart.',
        );
      });
    });

    describe('when the branch has not diverged', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('does not show the warning', () => {
        expect(findDivergedWarning().exists()).toBe(false);
      });
    });

    describe('when the ref changes', () => {
      beforeEach(async () => {
        divergedHandler.mockResolvedValueOnce(divergedResponse(true));
        createComponent();
        await waitForPromises();
      });

      describe('when the new branch has not diverged', () => {
        beforeEach(async () => {
          divergedHandler.mockResolvedValueOnce(divergedResponse(false));
          await wrapper.setProps({ currentRef: 'feature' });
        });

        it('hides the warning while checking the new branch', () => {
          expect(findDivergedWarning().exists()).toBe(false);
        });

        it('checks the new branch', async () => {
          await waitForPromises();

          expect(divergedHandler).toHaveBeenLastCalledWith({
            projectPath: 'group/project',
            ref: 'feature',
          });
          expect(findDivergedWarning().exists()).toBe(false);
        });
      });

      describe('when the check for the new branch fails', () => {
        const error = new Error('Network error');

        beforeEach(async () => {
          divergedHandler.mockRejectedValueOnce(error);
          await wrapper.setProps({ currentRef: 'feature' });
          await waitForPromises();
        });

        it('does not keep the warning from the previous branch', () => {
          expect(findDivergedWarning().exists()).toBe(false);
        });

        it('reports the error', () => {
          expect(captureException).toHaveBeenCalledWith(error);
        });
      });
    });

    describe.each`
      scenario                         | pullMirror                            | props
      ${'a tag is selected'}           | ${{}}                                 | ${{ currentRefType: 'tags' }}
      ${'the mirror has never synced'} | ${{ everUpdatedSuccessfully: false }} | ${{}}
    `('when $scenario', ({ pullMirror, props }) => {
      beforeEach(async () => {
        divergedHandler.mockResolvedValue(divergedResponse(true));
        createComponent({ pullMirror, props });
        await waitForPromises();
      });

      it('does not check or show the warning', () => {
        expect(divergedHandler).not.toHaveBeenCalled();
        expect(findDivergedWarning().exists()).toBe(false);
      });
    });
  });
});
