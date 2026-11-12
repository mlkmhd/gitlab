import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlDisclosureDropdownItem, GlSearchBoxByType, GlToggle } from '@gitlab/ui';
import { createAlert } from '~/alert';
import createMockApollo from 'helpers/mock_apollo_helper';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import WorkItemDisplaySettingsMetadata from '~/work_items/list/components/work_item_display_settings_metadata.vue';
import updateWorkItemListUserPreference from '~/work_items/graphql/update_work_item_list_user_preferences.mutation.graphql';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { isLoggedIn } from '~/lib/utils/common_utils';
import {
  WORK_ITEM_LIST_PREFERENCES_METADATA_FIELDS as ALL_METADATA_FIELDS,
  WORK_ITEM_LIST_PREFERENCES_METADATA_FIELDS_SORTED as ALL_METADATA_FIELDS_SORTED,
  METADATA_KEYS,
  VIEW_MODE_BOARD,
  VIEW_MODE_LIST,
} from '~/work_items/constants';

Vue.use(VueApollo);

jest.mock('~/alert');
jest.mock('~/lib/utils/common_utils', () => ({
  ...jest.requireActual('~/lib/utils/common_utils'),
  isLoggedIn: jest.fn(),
}));

// Board-only fields (e.g. AI session) never show up in the list view.
const WORK_ITEM_LIST_PREFERENCES_METADATA_FIELDS = ALL_METADATA_FIELDS.filter(
  (field) => !field.isBoardOnly,
);
const WORK_ITEM_LIST_PREFERENCES_METADATA_FIELDS_SORTED = ALL_METADATA_FIELDS_SORTED.filter(
  (field) => !field.isBoardOnly,
);

const firstAlphabeticalKey = WORK_ITEM_LIST_PREFERENCES_METADATA_FIELDS_SORTED[0].key;

describe('WorkItemDisplaySettingsMetadata', () => {
  let wrapper;
  let mockApolloProvider;
  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const namespacePreferencesHandler = jest.fn().mockResolvedValue({
    data: {
      workItemUserPreferenceUpdate: {
        __typename: 'WorkItemUserPreferenceUpdatePayload',
        errors: [],
        userPreferences: {
          __typename: 'UserPreferences',
          displaySettings: { hiddenMetadataKeys: [firstAlphabeticalKey] },
          sort: 'UPDATED_DESC',
        },
      },
    },
  });

  const createComponent = ({
    mountFn = shallowMountExtended,
    props = {},
    provide = {},
    namespaceHandler = namespacePreferencesHandler,
  } = {}) => {
    mockApolloProvider = createMockApollo([[updateWorkItemListUserPreference, namespaceHandler]]);

    wrapper = mountFn(WorkItemDisplaySettingsMetadata, {
      apolloProvider: mockApolloProvider,
      provide,
      propsData: {
        namespacePreferences: { hiddenMetadataKeys: [] },
        fullPath: 'gitlab-org/gitlab',
        isServiceDeskList: false,
        workItemTypeId: 'gid://gitlab/WorkItems::Type/8',
        sortKey: 'UPDATED_DESC',
        ...props,
      },
    });
  };

  const findShownSection = () => wrapper.findByTestId('shown-preferences');
  const findHiddenSection = () => wrapper.findByTestId('hidden-preferences');
  const findDropdownItems = () => wrapper.findAllComponents(GlDisclosureDropdownItem);
  const findToggles = () => wrapper.findAllComponents(GlToggle);
  const findFirstDropdownItem = () => findDropdownItems().at(0);
  const findSearchBox = () => wrapper.findComponent(GlSearchBoxByType);
  const findNoFieldsFound = () => wrapper.findByTestId('no-fields-found');

  beforeEach(() => {
    jest.clearAllMocks();
    isLoggedIn.mockReturnValue(true);
  });

  it('renders a toggle for every setting field', () => {
    createComponent();

    expect(findToggles()).toHaveLength(WORK_ITEM_LIST_PREFERENCES_METADATA_FIELDS.length);
  });

  it('renders all fields in the list view', () => {
    createComponent({ props: { viewMode: VIEW_MODE_LIST } });

    expect(findToggles()).toHaveLength(WORK_ITEM_LIST_PREFERENCES_METADATA_FIELDS.length);
  });

  it('renders only board-applicable metadata fields in the board view', () => {
    createComponent({ props: { viewMode: VIEW_MODE_BOARD } });

    const boardApplicableFields = ALL_METADATA_FIELDS.filter(
      (field) => field.isAvailableInBoard && !field.isBoardOnly,
    );
    const labels = findToggles().wrappers.map((t) => t.props('label'));

    expect(findToggles()).toHaveLength(boardApplicableFields.length);
    expect(labels).not.toContain('Comments');
    expect(labels).not.toContain('Popularity');
    expect(labels).not.toContain('AI session');
  });

  describe('AI session field', () => {
    const aiSessionLabel = ALL_METADATA_FIELDS.find(
      (f) => f.key === METADATA_KEYS.AI_SESSION,
    ).label;
    const toggleLabels = () => findToggles().wrappers.map((t) => t.props('label'));

    it('renders in the board view when the flag is on and Duo remote flows are available', () => {
      createComponent({
        props: { viewMode: VIEW_MODE_BOARD },
        provide: {
          duoRemoteFlowsAvailability: true,
          glFeatures: { planningViewBoardAiSessions: true },
        },
      });

      expect(toggleLabels()).toContain(aiSessionLabel);
    });

    it('does not render in the board view when the flag is off', () => {
      createComponent({
        props: { viewMode: VIEW_MODE_BOARD },
        provide: {
          duoRemoteFlowsAvailability: true,
          glFeatures: { planningViewBoardAiSessions: false },
        },
      });

      expect(toggleLabels()).not.toContain(aiSessionLabel);
    });

    it('does not render in the list view even when Duo remote flows are available', () => {
      createComponent({
        props: { viewMode: VIEW_MODE_LIST },
        provide: {
          duoRemoteFlowsAvailability: true,
          glFeatures: { planningViewBoardAiSessions: true },
        },
      });

      expect(toggleLabels()).not.toContain(aiSessionLabel);
    });
  });

  describe('shown/hidden grouping', () => {
    it('renders only the shown section when no fields are hidden', () => {
      createComponent({ mountFn: mountExtended });

      expect(findShownSection().exists()).toBe(true);
      expect(findHiddenSection().exists()).toBe(false);
    });

    it('renders both sections when at least one field is hidden', () => {
      createComponent({
        mountFn: mountExtended,
        props: { namespacePreferences: { hiddenMetadataKeys: [firstAlphabeticalKey] } },
      });

      expect(findShownSection().exists()).toBe(true);
      expect(findHiddenSection().exists()).toBe(true);
    });

    it('renders only the hidden section when every field is hidden', () => {
      createComponent({
        mountFn: mountExtended,
        props: {
          namespacePreferences: {
            hiddenMetadataKeys: WORK_ITEM_LIST_PREFERENCES_METADATA_FIELDS.map((f) => f.key),
          },
        },
      });

      expect(findShownSection().exists()).toBe(false);
      expect(findHiddenSection().exists()).toBe(true);
    });

    it('sorts toggles alphabetically by label across both sections', () => {
      const hidden = WORK_ITEM_LIST_PREFERENCES_METADATA_FIELDS_SORTED.slice(0, 2).map(
        (f) => f.key,
      );
      createComponent({
        mountFn: mountExtended,
        props: { namespacePreferences: { hiddenMetadataKeys: hidden } },
      });

      const labelsInOrder = findToggles().wrappers.map((t) => t.props('label'));
      const expectedHiddenLabels = WORK_ITEM_LIST_PREFERENCES_METADATA_FIELDS_SORTED.filter((f) =>
        hidden.includes(f.key),
      ).map((f) => f.label);
      const expectedShownLabels = WORK_ITEM_LIST_PREFERENCES_METADATA_FIELDS_SORTED.filter(
        (f) => !hidden.includes(f.key),
      ).map((f) => f.label);

      expect(labelsInOrder).toEqual([...expectedShownLabels, ...expectedHiddenLabels]);
    });
  });

  describe('fields search', () => {
    it('correctly filters toggles', async () => {
      createComponent({ mountFn: mountExtended });

      await findSearchBox().vm.$emit('input', 'lab');

      const labels = findToggles().wrappers.map((t) => t.props('label'));
      expect(labels).toEqual(['Labels']);
    });

    it('restores the full list when the search is cleared', async () => {
      createComponent({ mountFn: mountExtended });
      const totalFields = findToggles().length;

      await findSearchBox().vm.$emit('input', 'lab');
      expect(findToggles()).toHaveLength(1);

      await findSearchBox().vm.$emit('input', '');
      expect(findToggles()).toHaveLength(totalFields);
    });

    it('shows the no fields found state when no matches exist', async () => {
      createComponent({ mountFn: mountExtended });

      await findSearchBox().vm.$emit('input', 'no-match');

      expect(findNoFieldsFound().exists()).toBe(true);
      expect(findShownSection().exists()).toBe(false);
      expect(findHiddenSection().exists()).toBe(false);
    });
  });

  describe('when not on a saved view', () => {
    beforeEach(() => {
      createComponent({ props: { keepSettingsLocal: false } });
    });

    it('toggles metadata field visibility via the mutation', async () => {
      findFirstDropdownItem().vm.$emit('action');
      await waitForPromises();

      expect(namespacePreferencesHandler).toHaveBeenCalledWith({
        namespace: 'gitlab-org/gitlab',
        displaySettings: {
          hiddenMetadataKeys: [firstAlphabeticalKey],
        },
      });
    });

    it('shows an alert when the mutation fails', async () => {
      const error = new Error('Network error');
      const errorHandler = jest.fn().mockRejectedValue(error);
      createComponent({ namespaceHandler: errorHandler });

      findFirstDropdownItem().vm.$emit('action');
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'Something went wrong while saving the preference.',
        captureError: true,
        error,
      });
    });

    it('tracks work_item_metadata_field_hidden when a field is hidden', async () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findFirstDropdownItem().vm.$emit('action');
      await waitForPromises();

      expect(trackEventSpy).toHaveBeenCalledWith(
        'work_item_metadata_field_hidden',
        { property: firstAlphabeticalKey },
        undefined,
      );
    });
  });

  describe('when on a saved view', () => {
    beforeEach(() => {
      createComponent({ props: { keepSettingsLocal: true } });
    });

    it('updates settings without calling the mutation', async () => {
      findFirstDropdownItem().vm.$emit('action');
      await waitForPromises();

      expect(namespacePreferencesHandler).not.toHaveBeenCalled();
      expect(wrapper.emitted('update-settings')).toEqual([
        [{ hiddenMetadataKeys: [firstAlphabeticalKey] }],
      ]);
    });

    it('tracks work_item_metadata_field_hidden when a field is hidden', async () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findFirstDropdownItem().vm.$emit('action');
      await waitForPromises();

      expect(trackEventSpy).toHaveBeenCalledWith(
        'work_item_metadata_field_hidden',
        { property: firstAlphabeticalKey },
        undefined,
      );
    });

    it('does not track a hidden field for signed-out users', async () => {
      isLoggedIn.mockReturnValue(false);
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findFirstDropdownItem().vm.$emit('action');
      await waitForPromises();

      expect(wrapper.emitted('update-settings')).toHaveLength(1);
      expect(trackEventSpy).not.toHaveBeenCalled();
    });
  });
});
