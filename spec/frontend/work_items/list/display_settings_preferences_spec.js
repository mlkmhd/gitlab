import { createAlert } from '~/alert';
import {
  alertPreferenceError,
  applicableMetadataFields,
  persistMetadataPreference,
  persistSortPreference,
  persistSidePanelPreference,
  getSignedOutDisplaySettings,
  saveSignedOutDisplaySettings,
} from '~/work_items/list/display_settings_preferences';
import updateWorkItemListUserPreference from '~/work_items/graphql/update_work_item_list_user_preferences.mutation.graphql';
import updateWorkItemsDisplaySettings from '~/work_items/graphql/update_user_preferences.mutation.graphql';
import getUserWorkItemsPreferences from '~/work_items/graphql/get_user_preferences.query.graphql';
import {
  WORK_ITEM_LIST_PREFERENCES_METADATA_FIELDS_SORTED,
  METADATA_KEYS,
  VIEW_MODE_BOARD,
  VIEW_MODE_LIST,
} from '~/work_items/constants';

jest.mock('~/alert');

describe('display_settings_preferences', () => {
  const namespace = 'gitlab-org/gitlab';
  const workItemTypeId = 'gid://gitlab/WorkItems::Type/8';

  // Runs a mutation's `update` callback against a fake cache, so we can assert the immer patch.
  // `responseData` is the `{ data }` the mutation resolves with; `existingData` is the cached query.
  const runCacheUpdate = ({ update }, responseData, existingData) => {
    let result;
    const cache = {
      updateQuery: jest.fn((_options, updater) => {
        result = updater(existingData);
      }),
    };
    update(cache, responseData);
    return { cache, result };
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('alertPreferenceError', () => {
    it('shows a generic preference-save alert', () => {
      const error = new Error('boom');

      alertPreferenceError(error);

      expect(createAlert).toHaveBeenCalledWith({
        message: 'Something went wrong while saving the preference.',
        captureError: true,
        error,
      });
    });
  });

  describe('applicableMetadataFields', () => {
    const listFields = WORK_ITEM_LIST_PREFERENCES_METADATA_FIELDS_SORTED.filter(
      (field) => !field.isBoardOnly,
    );

    it('returns all non board-only fields for a non-service-desk list', () => {
      expect(applicableMetadataFields({ isServiceDeskList: false })).toEqual(listFields);
    });

    it('excludes the status field for a service desk list', () => {
      const keys = applicableMetadataFields({ isServiceDeskList: true }).map((f) => f.key);

      expect(keys).not.toContain(METADATA_KEYS.STATUS);
    });

    it('returns all non board-only fields for the list view, including weight and iteration', () => {
      expect(
        applicableMetadataFields({ isServiceDeskList: false, viewMode: VIEW_MODE_LIST }),
      ).toEqual(listFields);
    });

    describe('AI session field', () => {
      const keysFor = (params) => applicableMetadataFields(params).map((f) => f.key);

      it('is offered in the board view when AI sessions are available', () => {
        expect(keysFor({ viewMode: VIEW_MODE_BOARD, hasAiSessions: true })).toContain(
          METADATA_KEYS.AI_SESSION,
        );
      });

      it('is not offered in the board view without AI sessions', () => {
        expect(keysFor({ viewMode: VIEW_MODE_BOARD })).not.toContain(METADATA_KEYS.AI_SESSION);
      });

      it('is not offered in the list view', () => {
        expect(keysFor({ viewMode: VIEW_MODE_LIST, hasAiSessions: true })).not.toContain(
          METADATA_KEYS.AI_SESSION,
        );
      });
    });

    it('excludes fields that are not available on boards for the board view', () => {
      const fields = applicableMetadataFields({
        isServiceDeskList: false,
        viewMode: VIEW_MODE_BOARD,
      });

      expect(fields.every((f) => f.isAvailableInBoard)).toBe(true);
      expect(fields.map((f) => f.key)).not.toContain(METADATA_KEYS.COMMENTS);
      expect(fields.map((f) => f.key)).not.toContain(METADATA_KEYS.POPULARITY);
    });
  });

  describe('persistMetadataPreference', () => {
    const hiddenMetadataKeys = ['labels'];
    const displaySettings = { collapsedGroups: ['triage'], hiddenMetadataKeys };

    it('mutates with the namespace display settings and an optimistic response', () => {
      const apolloClient = { mutate: jest.fn().mockResolvedValue({}) };

      persistMetadataPreference({
        apolloClient,
        namespace,
        workItemTypeId,
        userPreferencesOnly: false,
        displaySettings,
        sort: 'UPDATED_DESC',
      });

      expect(apolloClient.mutate).toHaveBeenCalledWith(
        expect.objectContaining({
          mutation: updateWorkItemListUserPreference,
          variables: { namespace, displaySettings },
          optimisticResponse: {
            workItemUserPreferenceUpdate: {
              errors: [],
              userPreferences: {
                displaySettings,
                sort: 'UPDATED_DESC',
                __typename: 'WorkItemTypesUserPreference',
              },
              __typename: 'WorkItemUserPreferenceUpdatePayload',
            },
          },
        }),
      );
    });

    it('patches the cached display settings on update', () => {
      const apolloClient = { mutate: jest.fn() };
      persistMetadataPreference({
        apolloClient,
        namespace,
        workItemTypeId,
        userPreferencesOnly: false,
        displaySettings,
        sort: 'UPDATED_DESC',
      });

      const mutateArgs = apolloClient.mutate.mock.calls[0][0];
      const { cache, result } = runCacheUpdate(
        mutateArgs,
        {
          data: {
            workItemUserPreferenceUpdate: {
              userPreferences: { displaySettings: { hiddenMetadataKeys } },
            },
          },
        },
        { currentUser: { workItemPreferences: { displaySettings: { hiddenMetadataKeys: [] } } } },
      );

      expect(cache.updateQuery).toHaveBeenCalledWith(
        {
          query: getUserWorkItemsPreferences,
          variables: { namespace, workItemTypeId, userPreferencesOnly: false },
        },
        expect.any(Function),
      );
      expect(result.currentUser.workItemPreferences.displaySettings.hiddenMetadataKeys).toEqual(
        hiddenMetadataKeys,
      );
    });
  });

  describe('persistSortPreference', () => {
    it('mutates with the sort and omits userPreferencesOnly from the cache variables', () => {
      const apolloClient = { mutate: jest.fn() };

      persistSortPreference({ apolloClient, namespace, workItemTypeId, sort: 'CREATED_DESC' });

      const mutateArgs = apolloClient.mutate.mock.calls[0][0];
      expect(mutateArgs.mutation).toBe(updateWorkItemListUserPreference);
      expect(mutateArgs.variables).toEqual({ namespace, workItemTypeId, sort: 'CREATED_DESC' });

      const { cache, result } = runCacheUpdate(
        mutateArgs,
        { data: { workItemUserPreferenceUpdate: { userPreferences: { sort: 'CREATED_DESC' } } } },
        { currentUser: { workItemPreferencesWithType: { sort: 'UPDATED_DESC' } } },
      );

      expect(cache.updateQuery).toHaveBeenCalledWith(
        { query: getUserWorkItemsPreferences, variables: { namespace, workItemTypeId } },
        expect.any(Function),
      );
      expect(result.currentUser.workItemPreferencesWithType.sort).toBe('CREATED_DESC');
    });

    it('does not patch the cache when the mutation returns no preferences', () => {
      const apolloClient = { mutate: jest.fn() };
      persistSortPreference({ apolloClient, namespace, workItemTypeId, sort: 'CREATED_DESC' });

      const mutateArgs = apolloClient.mutate.mock.calls[0][0];
      const cache = { updateQuery: jest.fn() };
      mutateArgs.update(cache, {
        data: { workItemUserPreferenceUpdate: { userPreferences: null } },
      });

      expect(cache.updateQuery).not.toHaveBeenCalled();
    });
  });

  describe('persistSidePanelPreference', () => {
    it('mutates with the side panel input and patches the cached common preferences', () => {
      const apolloClient = { mutate: jest.fn() };

      persistSidePanelPreference({
        apolloClient,
        namespace,
        workItemTypeId,
        userPreferencesOnly: true,
        shouldOpenItemsInSidePanel: false,
      });

      const mutateArgs = apolloClient.mutate.mock.calls[0][0];
      expect(mutateArgs.mutation).toBe(updateWorkItemsDisplaySettings);
      expect(mutateArgs.variables).toEqual({
        input: { workItemsDisplaySettings: { shouldOpenItemsInSidePanel: false } },
      });

      const { cache, result } = runCacheUpdate(
        mutateArgs,
        {
          data: {
            userPreferencesUpdate: {
              userPreferences: { workItemsDisplaySettings: { shouldOpenItemsInSidePanel: false } },
            },
          },
        },
        {
          currentUser: {
            userPreferences: { workItemsDisplaySettings: { shouldOpenItemsInSidePanel: true } },
          },
        },
      );

      expect(cache.updateQuery).toHaveBeenCalledWith(
        {
          query: getUserWorkItemsPreferences,
          variables: { namespace, workItemTypeId, userPreferencesOnly: true },
        },
        expect.any(Function),
      );
      expect(
        result.currentUser.userPreferences.workItemsDisplaySettings.shouldOpenItemsInSidePanel,
      ).toBe(false);
    });
  });

  describe('signed-out display settings', () => {
    const storageKey = `${namespace}-work-items-display-settings`;
    const displaySettings = { namespacePreferences: { hiddenMetadataKeys: ['labels'] } };

    afterEach(() => {
      localStorage.clear();
    });

    it('returns an empty object when nothing is stored', () => {
      expect(getSignedOutDisplaySettings(namespace)).toEqual({});
    });

    it('returns the stored settings for the namespace', () => {
      saveSignedOutDisplaySettings(namespace, displaySettings);

      expect(JSON.parse(localStorage.getItem(storageKey))).toEqual(displaySettings);
      expect(getSignedOutDisplaySettings(namespace)).toEqual(displaySettings);
      expect(getSignedOutDisplaySettings('other/namespace')).toEqual({});
    });

    it('returns an empty object when the stored value is not valid JSON', () => {
      const warnSpy = jest.spyOn(console, 'warn').mockImplementation(() => {});
      localStorage.setItem(storageKey, '{not json');

      expect(getSignedOutDisplaySettings(namespace)).toEqual({});
      expect(warnSpy).toHaveBeenCalledTimes(1);
    });

    // The availability check writes a small test value, so only the real write fails here.
    it('does not throw when storage is too full for the settings', () => {
      const { setItem } = Storage.prototype;
      jest
        .spyOn(Storage.prototype, 'setItem')
        .mockImplementation(function setItemOrFail(key, value) {
          if (key === storageKey) throw new Error('QuotaExceededError');
          return setItem.call(this, key, value);
        });

      expect(() => saveSignedOutDisplaySettings(namespace, displaySettings)).not.toThrow();
    });
  });
});
