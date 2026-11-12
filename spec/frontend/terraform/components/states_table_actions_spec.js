import { GlDropdown, GlModal, GlSprintf, GlFormInput } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import InitCommandModal from '~/terraform/components/init_command_modal.vue';
import StateActions from '~/terraform/components/states_table_actions.vue';
import { MAX_LIST_COUNT } from '~/terraform/constants';
import deletePermanentlyStateMutation from '~/terraform/graphql/mutations/delete_permanently_state.mutation.graphql';
import lockStateMutation from '~/terraform/graphql/mutations/lock_state.mutation.graphql';
import removeStateMutation from '~/terraform/graphql/mutations/remove_state.mutation.graphql';
import restoreStateMutation from '~/terraform/graphql/mutations/restore_state.mutation.graphql';
import unlockStateMutation from '~/terraform/graphql/mutations/unlock_state.mutation.graphql';
import getStatesQuery from '~/terraform/graphql/queries/get_states.query.graphql';
import { getStatesResponse } from './mock_data';

Vue.use(VueApollo);

describe('StatesTableActions', () => {
  let apolloProvider;
  let deletePermanentlyResponse;
  let lockResponse;
  let removeResponse;
  let restoreResponse;
  let toast;
  let unlockResponse;
  let updateStateResponse;
  let wrapper;

  const defaultProps = {
    state: {
      id: 'gid/1',
      name: 'state-1',
      latestVersion: { downloadPath: '/path' },
      lockedAt: '2020-10-13T00:00:00Z',
    },
    terraformAdmin: true,
  };

  // Same variables TerraformList uses for the states list query.
  const listVariables = {
    projectPath: 'path/to/project',
    first: MAX_LIST_COUNT,
    after: null,
    last: null,
    before: null,
  };

  const createMockApolloProvider = (statesHandler, restoreHandler, deletePermanentlyHandler) => {
    deletePermanentlyResponse = deletePermanentlyHandler;

    lockResponse = jest
      .fn()
      .mockResolvedValue({ data: { terraformStateLock: { errors: ['There was an error'] } } });

    removeResponse = jest
      .fn()
      .mockResolvedValue({ data: { terraformStateDelete: { errors: [] } } });

    unlockResponse = jest
      .fn()
      .mockResolvedValue({ data: { terraformStateUnlock: { errors: [] } } });

    restoreResponse = restoreHandler;

    updateStateResponse = jest.fn().mockResolvedValue({});

    return createMockApollo(
      [
        [deletePermanentlyStateMutation, deletePermanentlyResponse],
        [lockStateMutation, lockResponse],
        [removeStateMutation, removeResponse],
        [restoreStateMutation, restoreResponse],
        [unlockStateMutation, unlockResponse],
        [getStatesQuery, statesHandler],
      ],
      {
        Mutation: {
          addDataToTerraformState: updateStateResponse,
        },
      },
    );
  };

  const createComponent = async (
    propsData = defaultProps,
    statesHandler = jest.fn().mockResolvedValue(getStatesResponse),
    {
      delayedDeletion = false,
      restoreHandler = jest
        .fn()
        .mockResolvedValue({ data: { terraformStateRestore: { errors: [] } } }),
      deletePermanentlyHandler = jest
        .fn()
        .mockResolvedValue({ data: { terraformStateDeletePermanently: { errors: [] } } }),
    } = {},
  ) => {
    apolloProvider = createMockApolloProvider(
      statesHandler,
      restoreHandler,
      deletePermanentlyHandler,
    );

    // refetchQueries targets the active states list query, which is normally watched by TerraformList.
    apolloProvider.defaultClient
      .watchQuery({ query: getStatesQuery, variables: listVariables })
      .subscribe(() => {});

    toast = jest.fn();

    wrapper = shallowMount(StateActions, {
      apolloProvider,
      propsData,
      provide: {
        projectPath: 'path/to/project',
        glFeatures: { terraformStateDelayedDeletion: delayedDeletion },
      },
      mocks: { $toast: { show: toast } },
      stubs: { GlDropdown, GlModal, GlSprintf },
    });

    await nextTick();
  };

  const buildState = (id, name, extra = {}) => ({
    __typename: 'TerraformState',
    _showDetails: false,
    errorMessages: [],
    loadingLock: false,
    loadingRemove: false,
    loadingRestore: false,
    id,
    name,
    lockedAt: null,
    updatedAt: null,
    deletedAt: null,
    permanentDeletionAt: null,
    lockedByUser: null,
    latestVersion: null,
    ...extra,
  });

  const buildStatesResponse = (nodes) => ({
    data: {
      project: {
        __typename: 'Project',
        id: 'project-1',
        terraformStates: {
          __typename: 'TerraformStateConnection',
          count: nodes.length,
          nodes,
          pageInfo: {
            __typename: 'PageInfo',
            hasNextPage: false,
            hasPreviousPage: false,
            startCursor: '',
            endCursor: '',
          },
        },
      },
    },
  });

  const readCachedStates = () =>
    apolloProvider.defaultClient.readQuery({ query: getStatesQuery, variables: listVariables })
      .project.terraformStates;

  const readCachedStateIds = () => readCachedStates().nodes.map(({ id }) => id);

  const findActionsDropdown = () => wrapper.findComponent(GlDropdown);
  const findCopyBtn = () =>
    wrapper.findComponent('[data-testid="terraform-state-copy-init-command"]');
  const findCopyModal = () => wrapper.findComponent(InitCommandModal);
  const findLockBtn = () => wrapper.findComponent('[data-testid="terraform-state-lock"]');
  const findUnlockBtn = () => wrapper.findComponent('[data-testid="terraform-state-unlock"]');
  const findDownloadBtn = () => wrapper.find('[data-testid="terraform-state-download"]');
  const findRestoreBtn = () => wrapper.findComponent('[data-testid="terraform-state-restore"]');
  const findRemoveBtn = () => wrapper.findComponent('[data-testid="terraform-state-remove"]');
  const findDeletePermanentlyBtn = () =>
    wrapper.findComponent('[data-testid="terraform-state-delete-permanently"]');
  const findRemoveModal = () => wrapper.findComponent(GlModal);
  const findFormInput = () => wrapper.findComponent(GlFormInput);

  const deletePermanentlyAndConfirm = async () => {
    findDeletePermanentlyBtn().vm.$emit('click');
    await nextTick();
    await findFormInput().vm.$emit('input', defaultProps.state.name);
    findRemoveModal().vm.$emit('ok');
    await waitForPromises();
  };

  beforeEach(() => {
    return createComponent();
  });

  afterEach(() => {
    deletePermanentlyResponse = null;
    lockResponse = null;
    removeResponse = null;
    restoreResponse = null;
    toast = null;
    unlockResponse = null;
    updateStateResponse = null;
  });

  describe('when the state is loading', () => {
    describe('when lock/unlock is processing', () => {
      beforeEach(() => {
        return createComponent({
          ...defaultProps,
          state: {
            ...defaultProps.state,
            loadingLock: true,
          },
        });
      });

      it('disables the actions dropdown', () => {
        expect(findActionsDropdown().props('disabled')).toBe(true);
      });
    });

    describe('when remove is processing', () => {
      beforeEach(() => {
        return createComponent({
          ...defaultProps,
          state: {
            ...defaultProps.state,
            loadingRemove: true,
          },
        });
      });

      it('disables the actions dropdown', () => {
        expect(findActionsDropdown().props('disabled')).toBe(true);
      });
    });
  });

  describe('copy command button', () => {
    it('displays a copy init command button', () => {
      expect(findCopyBtn().text()).toBe('Copy Terraform init command');
    });

    describe('when clicking the copy init command button', () => {
      beforeEach(() => {
        findCopyBtn().vm.$emit('click');

        return waitForPromises();
      });

      it('opens the modal', () => {
        expect(findCopyModal().exists()).toBe(true);
        expect(findCopyModal().isVisible()).toBe(true);
      });
    });
  });

  describe('download button', () => {
    it('displays a download button', () => {
      expect(findDownloadBtn().text()).toBe('Download JSON');
    });

    describe('when state does not have a latestVersion', () => {
      beforeEach(() => {
        return createComponent({
          ...defaultProps,
          state: {
            id: 'gid/1',
            name: 'state-1',
            latestVersion: null,
          },
        });
      });

      it('does not display a download button', () => {
        expect(findDownloadBtn().exists()).toBe(false);
      });
    });
  });

  describe('unlock button', () => {
    it('displays an unlock button', () => {
      expect(findUnlockBtn().text()).toBe('Unlock');
      expect(findLockBtn().exists()).toBe(false);
    });

    describe('when clicking the unlock button', () => {
      beforeEach(() => {
        findUnlockBtn().vm.$emit('click');

        return waitForPromises();
      });

      it('calls the unlock mutation', () => {
        expect(unlockResponse).toHaveBeenCalledWith({
          stateID: defaultProps.state.id,
        });
      });
    });
  });

  describe('lock button', () => {
    const unlockedProps = {
      ...defaultProps,
      state: {
        id: 'gid/2',
        name: 'state-2',
        latestVersion: null,
        lockedAt: null,
      },
    };

    beforeEach(() => {
      return createComponent(unlockedProps);
    });

    it('displays a lock button', () => {
      expect(findLockBtn().text()).toBe('Lock');
      expect(findUnlockBtn().exists()).toBe(false);
    });

    describe('when clicking the lock button', () => {
      beforeEach(() => {
        findLockBtn().vm.$emit('click');

        return waitForPromises();
      });

      it('calls the lock mutation', () => {
        expect(lockResponse).toHaveBeenCalledWith({
          stateID: unlockedProps.state.id,
        });
      });

      it('calls mutations to set loading and errors', () => {
        // loading update
        expect(updateStateResponse).toHaveBeenNthCalledWith(
          1,
          {},
          {
            terraformState: {
              ...unlockedProps.state,
              _showDetails: false,
              errorMessages: [],
              loadingLock: true,
              loadingRemove: false,
            },
          },
          // Apollo fields
          expect.any(Object),
          expect.any(Object),
        );

        // final update
        expect(updateStateResponse).toHaveBeenNthCalledWith(
          2,
          {},
          {
            terraformState: {
              ...unlockedProps.state,
              _showDetails: true,
              errorMessages: ['There was an error'],
              loadingLock: false,
              loadingRemove: false,
              loadingRestore: false,
            },
          },
          // Apollo fields
          expect.any(Object),
          expect.any(Object),
        );
      });
    });
  });

  describe('remove button', () => {
    it('displays a remove button', () => {
      expect(findRemoveBtn().text()).toBe('Remove');
    });

    describe('when clicking the remove button', () => {
      beforeEach(() => {
        findRemoveBtn().vm.$emit('click');
        return waitForPromises();
      });

      it('displays a remove modal', () => {
        expect(findRemoveModal().text()).toContain(
          `You are about to remove the state file ${defaultProps.state.name}`,
        );
      });

      it('warns that the action cannot be undone', () => {
        expect(findRemoveModal().text()).toContain('This action cannot be undone.');
      });

      describe('when submitting the remove modal', () => {
        describe('when state name is missing', () => {
          beforeEach(() => {
            findRemoveModal().vm.$emit('ok');
            return waitForPromises();
          });

          it('does not call the remove mutation', () => {
            expect(removeResponse).not.toHaveBeenCalledWith();
          });
        });

        describe('when state name is present', () => {
          beforeEach(async () => {
            await findFormInput().vm.$emit('input', defaultProps.state.name);

            findRemoveModal().vm.$emit('ok');

            await waitForPromises();
          });

          it('calls the remove mutation', () => {
            expect(removeResponse).toHaveBeenCalledWith({ stateID: defaultProps.state.id });
          });

          it('calls the toast action', () => {
            expect(toast).toHaveBeenCalledWith(`${defaultProps.state.name} successfully removed`);
          });

          it('calls mutations to set loading and errors', () => {
            // loading update
            expect(updateStateResponse).toHaveBeenNthCalledWith(
              1,
              {},
              {
                terraformState: {
                  ...defaultProps.state,
                  _showDetails: false,
                  errorMessages: [],
                  loadingLock: false,
                  loadingRemove: true,
                },
              },
              // Apollo fields
              expect.any(Object),
              expect.any(Object),
            );

            // final update
            expect(updateStateResponse).toHaveBeenNthCalledWith(
              2,
              {},
              {
                terraformState: {
                  ...defaultProps.state,
                  _showDetails: false,
                  errorMessages: [],
                  loadingLock: false,
                  loadingRemove: false,
                  loadingRestore: false,
                },
              },
              // Apollo fields
              expect.any(Object),
              expect.any(Object),
            );
          });
        });
      });
    });

    describe('when the removed state is no longer returned by the states list query', () => {
      let statesHandler;

      beforeEach(async () => {
        statesHandler = jest
          .fn()
          .mockResolvedValueOnce(
            buildStatesResponse([buildState('gid/1', 'state-1'), buildState('gid/2', 'state-2')]),
          )
          .mockResolvedValue(buildStatesResponse([buildState('gid/2', 'state-2')]));

        await createComponent(defaultProps, statesHandler);
        await waitForPromises();

        findRemoveBtn().vm.$emit('click');
        await waitForPromises();

        await findFormInput().vm.$emit('input', defaultProps.state.name);
        findRemoveModal().vm.$emit('ok');
        await waitForPromises();
      });

      it('refetches the active list query using its own pagination variables', () => {
        expect(statesHandler).toHaveBeenCalledTimes(2);
        expect(statesHandler).toHaveBeenLastCalledWith(listVariables);
      });

      it('replaces the cached list so the removed state is dropped', () => {
        expect(readCachedStateIds()).toEqual(['gid/2']);
      });
    });
  });

  describe('when terraform_state_delayed_deletion is enabled', () => {
    const delayedDeletion = { delayedDeletion: true };

    describe('remove modal wording', () => {
      describe('when the state has versions', () => {
        beforeEach(async () => {
          await createComponent(defaultProps, undefined, delayedDeletion);
          findRemoveBtn().vm.$emit('click');
          await waitForPromises();
        });

        it('explains the state can be restored within 7 days', () => {
          expect(findRemoveModal().text()).toContain(
            'The state will be scheduled for deletion. You can restore it from the state list within 7 days.',
          );
          expect(findRemoveModal().text()).not.toContain('This action cannot be undone.');
        });
      });

      describe('when the state has no versions', () => {
        beforeEach(async () => {
          await createComponent(
            { ...defaultProps, state: { ...defaultProps.state, latestVersion: null } },
            undefined,
            delayedDeletion,
          );
          findRemoveBtn().vm.$emit('click');
          await waitForPromises();
        });

        it('warns that the action cannot be undone', () => {
          expect(findRemoveModal().text()).toContain('This action cannot be undone.');
        });
      });
    });

    describe('when the state is not deleted', () => {
      beforeEach(() => {
        return createComponent(defaultProps, undefined, delayedDeletion);
      });

      it('does not display a restore button', () => {
        expect(findRestoreBtn().exists()).toBe(false);
      });

      it('does not display a delete permanently button', () => {
        expect(findDeletePermanentlyBtn().exists()).toBe(false);
      });

      it('displays a remove button', () => {
        expect(findRemoveBtn().exists()).toBe(true);
      });
    });

    describe('when the state is deleted', () => {
      const deletedProps = {
        ...defaultProps,
        state: { ...defaultProps.state, deletedAt: '2026-10-20T00:00:00Z' },
      };

      describe('when the user does not have an administrator role', () => {
        beforeEach(() => {
          return createComponent(
            { ...deletedProps, terraformAdmin: false },
            undefined,
            delayedDeletion,
          );
        });

        it('does not display a restore button', () => {
          expect(findRestoreBtn().exists()).toBe(false);
        });

        it('does not display a delete permanently button', () => {
          expect(findDeletePermanentlyBtn().exists()).toBe(false);
        });

        it('does not display the actions dropdown', () => {
          expect(findActionsDropdown().exists()).toBe(false);
        });
      });

      describe('when restore is processing', () => {
        beforeEach(() => {
          return createComponent(
            { ...deletedProps, state: { ...deletedProps.state, loadingRestore: true } },
            undefined,
            delayedDeletion,
          );
        });

        it('disables the actions dropdown', () => {
          expect(findActionsDropdown().props('disabled')).toBe(true);
        });
      });

      describe('when the user has an administrator role', () => {
        beforeEach(() => {
          return createComponent(deletedProps, undefined, delayedDeletion);
        });

        it('displays a restore button', () => {
          expect(findRestoreBtn().text()).toBe('Restore');
        });

        it('does not display a remove button', () => {
          expect(findRemoveBtn().exists()).toBe(false);
        });

        it('does not display the copy init command, download, lock or unlock buttons', () => {
          expect(findCopyBtn().exists()).toBe(false);
          expect(findDownloadBtn().exists()).toBe(false);
          expect(findLockBtn().exists()).toBe(false);
          expect(findUnlockBtn().exists()).toBe(false);
        });

        describe('when clicking the restore button', () => {
          beforeEach(() => {
            findRestoreBtn().vm.$emit('click');
            return waitForPromises();
          });

          it('calls the restore mutation', () => {
            expect(restoreResponse).toHaveBeenCalledWith({ stateID: deletedProps.state.id });
          });

          it('calls the toast action', () => {
            expect(toast).toHaveBeenCalledWith('state-1 successfully restored');
          });

          it('sets the loading state, then clears it', () => {
            expect(updateStateResponse).toHaveBeenNthCalledWith(
              1,
              {},
              {
                terraformState: {
                  ...deletedProps.state,
                  _showDetails: false,
                  errorMessages: [],
                  loadingLock: false,
                  loadingRemove: false,
                  loadingRestore: true,
                },
              },
              expect.any(Object),
              expect.any(Object),
            );

            expect(updateStateResponse).toHaveBeenNthCalledWith(
              2,
              {},
              {
                terraformState: {
                  ...deletedProps.state,
                  _showDetails: false,
                  errorMessages: [],
                  loadingLock: false,
                  loadingRemove: false,
                  loadingRestore: false,
                },
              },
              expect.any(Object),
              expect.any(Object),
            );
          });
        });

        describe('when the restore mutation returns errors', () => {
          beforeEach(async () => {
            await createComponent(deletedProps, undefined, {
              ...delayedDeletion,
              restoreHandler: jest
                .fn()
                .mockResolvedValue({ data: { terraformStateRestore: { errors: ['Not found'] } } }),
            });
            findRestoreBtn().vm.$emit('click');
            await waitForPromises();
          });

          it('surfaces the error and does not show a toast', () => {
            expect(toast).not.toHaveBeenCalled();
            expect(updateStateResponse).toHaveBeenLastCalledWith(
              {},
              {
                terraformState: expect.objectContaining({
                  _showDetails: true,
                  errorMessages: ['Not found'],
                  loadingRestore: false,
                }),
              },
              expect.any(Object),
              expect.any(Object),
            );
          });
        });

        it('displays a delete permanently button', () => {
          expect(findDeletePermanentlyBtn().text()).toBe('Delete permanently');
        });

        it('does not show the remove modal', () => {
          expect(findRemoveModal().props('visible')).toBe(false);
        });

        describe('when clicking the delete permanently button', () => {
          beforeEach(async () => {
            findDeletePermanentlyBtn().vm.$emit('click');
            await nextTick();
          });

          it('opens the remove modal with the delete permanently wording', () => {
            expect(findRemoveModal().props('visible')).toBe(true);
            expect(findRemoveModal().text()).toContain(
              'Are you sure you want to remove the Terraform State state-1 permanently?',
            );
            expect(findRemoveModal().text()).toContain(
              'This will permanently delete the state file state-1 and all its versions. This action cannot be undone.',
            );
            expect(findRemoveModal().props('actionPrimary').text).toBe('Delete permanently');
          });

          it('does not call the delete permanently mutation before confirmation', () => {
            expect(deletePermanentlyResponse).not.toHaveBeenCalled();
          });

          describe('when submitting the modal without the state name', () => {
            beforeEach(() => {
              findRemoveModal().vm.$emit('ok');
              return waitForPromises();
            });

            it('does not call the delete permanently mutation', () => {
              expect(deletePermanentlyResponse).not.toHaveBeenCalled();
            });
          });

          describe('when confirming the modal', () => {
            beforeEach(async () => {
              await findFormInput().vm.$emit('input', deletedProps.state.name);
              findRemoveModal().vm.$emit('ok');
              await waitForPromises();
            });

            it('calls the delete permanently mutation', () => {
              expect(deletePermanentlyResponse).toHaveBeenCalledWith({
                stateID: deletedProps.state.id,
              });
            });

            it('does not call the remove mutation', () => {
              expect(removeResponse).not.toHaveBeenCalled();
            });

            it('closes the modal', () => {
              expect(findRemoveModal().props('visible')).toBe(false);
            });

            it('calls the toast action', () => {
              expect(toast).toHaveBeenCalledWith('state-1 permanently deleted');
            });

            it('sets the loading state, then clears it', () => {
              expect(updateStateResponse).toHaveBeenNthCalledWith(
                1,
                {},
                {
                  terraformState: {
                    ...deletedProps.state,
                    _showDetails: false,
                    errorMessages: [],
                    loadingLock: false,
                    loadingRemove: true,
                  },
                },
                expect.any(Object),
                expect.any(Object),
              );

              expect(updateStateResponse).toHaveBeenNthCalledWith(
                2,
                {},
                {
                  terraformState: {
                    ...deletedProps.state,
                    _showDetails: false,
                    errorMessages: [],
                    loadingLock: false,
                    loadingRemove: false,
                    loadingRestore: false,
                  },
                },
                expect.any(Object),
                expect.any(Object),
              );
            });
          });
        });

        describe('when the states list still returns the state after the mutation', () => {
          let statesHandler;

          beforeEach(async () => {
            const { deletedAt } = deletedProps.state;

            // The backend deletes asynchronously, so the list can still include the state.
            statesHandler = jest
              .fn()
              .mockResolvedValue(
                buildStatesResponse([
                  buildState('gid/1', 'state-1', { deletedAt }),
                  buildState('gid/2', 'state-2'),
                ]),
              );

            await createComponent(deletedProps, statesHandler, delayedDeletion);
            await waitForPromises();

            await deletePermanentlyAndConfirm();
          });

          it('does not refetch the states list', () => {
            expect(statesHandler).toHaveBeenCalledTimes(1);
          });

          it('removes the state from the cached list and decrements the count', () => {
            expect(readCachedStateIds()).toEqual(['gid/2']);
            expect(readCachedStates().count).toBe(1);
          });
        });

        describe('when the delete permanently mutation returns errors', () => {
          beforeEach(async () => {
            await createComponent(deletedProps, undefined, {
              ...delayedDeletion,
              deletePermanentlyHandler: jest.fn().mockResolvedValue({
                data: { terraformStateDeletePermanently: { errors: ['Not found'] } },
              }),
            });
            await deletePermanentlyAndConfirm();
          });

          it('surfaces the error and does not show a toast', () => {
            expect(toast).not.toHaveBeenCalled();
            expect(updateStateResponse).toHaveBeenLastCalledWith(
              {},
              {
                terraformState: expect.objectContaining({
                  _showDetails: true,
                  errorMessages: ['Not found'],
                  loadingRemove: false,
                }),
              },
              expect.any(Object),
              expect.any(Object),
            );
          });
        });

        describe('when the delete permanently mutation fails', () => {
          beforeEach(async () => {
            await createComponent(deletedProps, undefined, {
              ...delayedDeletion,
              deletePermanentlyHandler: jest.fn().mockRejectedValue(new Error('Network error')),
            });
            await deletePermanentlyAndConfirm();
          });

          it('surfaces a generic error', () => {
            expect(updateStateResponse).toHaveBeenLastCalledWith(
              {},
              {
                terraformState: expect.objectContaining({
                  _showDetails: true,
                  errorMessages: ['An error occurred while changing the state file'],
                  loadingRemove: false,
                }),
              },
              expect.any(Object),
              expect.any(Object),
            );
          });
        });

        describe('when the restore mutation fails', () => {
          beforeEach(async () => {
            await createComponent(deletedProps, undefined, {
              ...delayedDeletion,
              restoreHandler: jest.fn().mockRejectedValue(new Error('Network error')),
            });
            findRestoreBtn().vm.$emit('click');
            await waitForPromises();
          });

          it('surfaces a generic error', () => {
            expect(updateStateResponse).toHaveBeenLastCalledWith(
              {},
              {
                terraformState: expect.objectContaining({
                  _showDetails: true,
                  errorMessages: ['An error occurred while changing the state file'],
                  loadingRestore: false,
                }),
              },
              expect.any(Object),
              expect.any(Object),
            );
          });
        });
      });
    });
  });

  describe('when terraform_state_delayed_deletion is disabled and the state is deleted', () => {
    beforeEach(() => {
      return createComponent({
        ...defaultProps,
        state: { ...defaultProps.state, deletedAt: '2026-10-20T00:00:00Z' },
      });
    });

    it('does not display a restore button', () => {
      expect(findRestoreBtn().exists()).toBe(false);
    });

    it('does not display a delete permanently button', () => {
      expect(findDeletePermanentlyBtn().exists()).toBe(false);
    });

    it('displays a remove button', () => {
      expect(findRemoveBtn().exists()).toBe(true);
    });

    it('still displays the copy init command, download and unlock buttons', () => {
      expect(findCopyBtn().exists()).toBe(true);
      expect(findDownloadBtn().exists()).toBe(true);
      expect(findUnlockBtn().exists()).toBe(true);
    });
  });

  describe('when the user has an administrator role', () => {
    beforeEach(() => {
      return createComponent();
    });

    it('displays all available action buttons', () => {
      expect(findCopyBtn().exists()).toBe(true);
      expect(findDownloadBtn().exists()).toBe(true);
      expect(findUnlockBtn().exists()).toBe(true);
      expect(findRemoveBtn().exists()).toBe(true);
    });
  });

  describe('when the user does not have an administrator role', () => {
    beforeEach(() => {
      return createComponent({ ...defaultProps, terraformAdmin: false });
    });

    it('displays "copy init command" and "download" action buttons', () => {
      expect(findCopyBtn().exists()).toBe(true);
      expect(findDownloadBtn().exists()).toBe(true);
      expect(findUnlockBtn().exists()).toBe(false);
      expect(findRemoveBtn().exists()).toBe(false);
    });
  });
});
