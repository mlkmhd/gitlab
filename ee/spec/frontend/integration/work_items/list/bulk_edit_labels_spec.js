import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import WorkItemsRoot from '~/work_items/components/app.vue';
import { createRouter } from '~/work_items/router';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import { restWorkItemsList } from 'ee_jest/integration/work_items/fixture_variants';
import { createPortalElement } from 'ee_jest/integration/work_items/test_helpers';
import { activateVariant, setFeatureFlags } from 'ee_jest/integration/helpers/setup_utils';
import {
  assignRouter,
  fullMount,
  findByGraphQLId,
  getText,
  screen,
  waitAndClick,
  waitForAssertion,
  waitForSetup,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import { useListFixture } from './filter_shared_test_helpers';
import { PROJECT_PATH, GROUP_PATH } from './filter_test_constants';

const listNodes = restWorkItemsList.OPENED;
const idByTitle = (title) => listNodes.find((node) => node.title === title)?.global_id;

// Each already has a known label state in the base fixture, so these cases don't need a
// dedicated list fixture variant. The ids are the same under the GROUP fixture too: it is
// the same project's items, requested with include_descendants.
const UNLABELLED_ISSUE_ID = idByTitle('Dependent test issue');
const LABELLED_ISSUE_ID = idByTitle('Second test issue'); // carries "To Do"
const LABELLED_TASK_ID = idByTitle('Child task'); // carries "Doing"

Vue.use(VueApollo);

// One router for both scopes below: `createRouter`'s base depends only on `routerPath`,
// which is the same either way, and a second concurrent VueRouter 'history' instance in
// the same jsdom window leaves one of the two stuck unrouted.
const router = assignRouter(createRouter, {
  fullPath: PROJECT_PATH,
  routerPath: 'work_items',
});

describe.each`
  scope        | isGroup  | fullPath
  ${'project'} | ${false} | ${PROJECT_PATH}
  ${'group'}   | ${true}  | ${GROUP_PATH}
`('Work items list - bulk edit labels ($scope)', ({ isGroup, fullPath }) => {
  const findCard = (id) => findByGraphQLId(id, getIdFromGraphQLId);
  const findLabelChips = (id) =>
    [...findCard(id).querySelectorAll('.gl-label')].map((el) => getText(el));

  let wrapper;

  const createComponent = () => {
    setFeatureFlags({ workItemRestApiFrontendUsers: true });

    wrapper = fullMount(WorkItemsRoot, {
      router,
      propsData: {
        rootPageFullPath: fullPath,
      },
      apolloProvider,
      provide: {
        isGroup,
        fullPath,
        groupPath: GROUP_PATH,
        workItemType: undefined,
        isSignedIn: true,
        initialSort: 'created_desc',
        isServiceDeskSupported: false,
        workItemsSavedViewsEnabled: false,
      },
    });
  };

  const startBulkEdit = async () => {
    createComponent();

    // The first mount compiles and fetches every list query, which a starved CI runner
    // can stretch past a test's wait. That is boot, so it runs on the setup budget.
    await waitForSetup(() => {
      const card = findCard(UNLABELLED_ISSUE_ID);
      expect(card).not.toBe(null);
    });

    await waitAndClick(() => screen.queryByTestId('bulk-edit-start-button'));
  };

  // Tears down the mounted app and remounts it, so the remount's initial queries
  // (including `getAvailableBulkEditWidgets`) run fresh against the mock's current
  // state, the way a page reload would.
  const reloadAndStartBulkEdit = async () => {
    wrapper.destroy();
    document.body.innerHTML = '';
    await startBulkEdit();
  };

  const checkItem = async (id) => {
    const title = listNodes.find((node) => node.global_id === id)?.title;
    await waitAndClick(() => screen.queryByRole('checkbox', { name: title }));
  };

  // The "Add labels" and "Remove labels" dropdowns both start with the same toggle text,
  // so they are told apart by the `data-testid` their wrapping form group renders
  const selectLabels = async (testId, labelTitles) => {
    const toggle = () => {
      const button = within(screen.queryByTestId(testId)).queryByTestId('base-dropdown-toggle');
      return button?.getAttribute('aria-disabled') === 'true' ? null : button;
    };

    await waitAndClick(toggle);
    for (const title of labelTitles) {
      // eslint-disable-next-line no-await-in-loop
      await waitForAssertion(() => {
        const options = within(screen.queryByTestId(testId)).queryAllByRole('option', {
          name: title,
        });
        // Scoped to this dropdown's own container and to the first match
        const option = options[0];
        expect(option).not.toBe(undefined);
        // `waitForAssertion` retries this whole callback until the toggle text updates, so a
        // slow re-render would otherwise cause a second click here, which deselects the
        // option it just selected.
        if (option.getAttribute('aria-selected') !== 'true') {
          option.click();
        }
        expect(getText(toggle())).toContain(title);
      });
    }
  };

  const addLabels = (labelTitles) => selectLabels('bulk-edit-add-labels', labelTitles);
  const removeLabels = (labelTitles) => selectLabels('bulk-edit-remove-labels', labelTitles);

  const updateSelected = async () => {
    await waitAndClick(() => screen.queryByRole('button', { name: 'Update selected' }));
  };

  // Sets the state the list's refetch (after the bulk update) should see.
  const useAfterUpdateFixture = (variant) => useListFixture(variant);

  beforeAll(() => {
    createPortalElement();
  });

  beforeEach(async () => {
    useListFixture(isGroup ? 'GROUP' : 'OPENED');
    if (isGroup) activateVariant('workItemMetadataEE', 'GROUP');
    await apolloProvider.defaultClient.cache.reset();
  });

  it('assigns a single label to an unlabelled work item', async () => {
    await startBulkEdit();
    await checkItem(UNLABELLED_ISSUE_ID);
    await addLabels(['Doing']);
    useAfterUpdateFixture('AFTER_ADD_DOING_TO_UNLABELLED');
    await updateSelected();

    await waitForAssertion(() => {
      expect(findLabelChips(UNLABELLED_ISSUE_ID)).toEqual(['Doing']);
    });
  });

  it('assigns a label to multiple checked work items', async () => {
    await startBulkEdit();
    await checkItem(UNLABELLED_ISSUE_ID);
    await checkItem(LABELLED_ISSUE_ID);
    await addLabels(['Doing']);
    useAfterUpdateFixture('AFTER_ADD_DOING_TO_TWO');
    await updateSelected();

    await waitForAssertion(() => {
      expect(findLabelChips(UNLABELLED_ISSUE_ID)).toEqual(['Doing']);
      expect(findLabelChips(LABELLED_ISSUE_ID).sort()).toEqual(['Doing', 'To Do']);
    });
  });

  it('assigns multiple labels to one work item', async () => {
    await startBulkEdit();
    await checkItem(UNLABELLED_ISSUE_ID);
    await addLabels(['To Do', 'Doing']);
    useAfterUpdateFixture('AFTER_ADD_TWO_TO_UNLABELLED');
    await updateSelected();

    await waitForAssertion(() => {
      expect(findLabelChips(UNLABELLED_ISSUE_ID).sort()).toEqual(['Doing', 'To Do']);
    });
  });

  it('assigns a label on mixed work item types', async () => {
    await startBulkEdit();
    await checkItem(UNLABELLED_ISSUE_ID); // an Issue
    await checkItem(LABELLED_TASK_ID); // a Task
    await addLabels(['To Do']);
    useAfterUpdateFixture('AFTER_ADD_TODO_MIXED');
    await updateSelected();

    await waitForAssertion(() => {
      expect(findLabelChips(UNLABELLED_ISSUE_ID)).toEqual(['To Do']);
      expect(findLabelChips(LABELLED_TASK_ID).sort()).toEqual(['Doing', 'To Do']);
    });
  });

  it('unassigns a label from a work item', async () => {
    await startBulkEdit();
    await checkItem(LABELLED_ISSUE_ID);
    await removeLabels(['To Do']);
    useAfterUpdateFixture('AFTER_REMOVE_TODO');
    await updateSelected();

    await waitForAssertion(() => {
      expect(findLabelChips(LABELLED_ISSUE_ID)).toEqual([]);
    });
  });

  it('unassigns labels from multiple work items', async () => {
    await startBulkEdit();
    await checkItem(LABELLED_ISSUE_ID);
    await checkItem(LABELLED_TASK_ID);
    // One call, not two: the second `waitAndClick(toggle)` in a separate call would close
    // the listbox instead of reopening it, since multi-select never auto-closes on select.
    await removeLabels(['To Do', 'Doing']);
    useAfterUpdateFixture('AFTER_REMOVE_FROM_TWO');
    await updateSelected();

    await waitForAssertion(() => {
      expect(findLabelChips(LABELLED_ISSUE_ID)).toEqual([]);
      expect(findLabelChips(LABELLED_TASK_ID)).toEqual([]);
    });
  });

  it('unassigns multiple labels from one work item', async () => {
    // The base fixture has no item carrying two labels, so this bulk-assigns a second
    // label first, then unassigns both in a separate update, mirroring a page reload
    // between the two steps.
    await startBulkEdit();
    await checkItem(LABELLED_ISSUE_ID);
    await addLabels(['Doing']);
    useAfterUpdateFixture('AFTER_ADD_DOING_TO_TWO');
    await updateSelected();

    await waitForAssertion(() => {
      expect(findLabelChips(LABELLED_ISSUE_ID).sort()).toEqual(['Doing', 'To Do']);
    });

    await reloadAndStartBulkEdit();
    await checkItem(LABELLED_ISSUE_ID);
    await removeLabels(['To Do', 'Doing']);
    useAfterUpdateFixture('AFTER_REMOVE_TODO');
    await updateSelected();

    await waitForAssertion(() => {
      expect(findLabelChips(LABELLED_ISSUE_ID)).toEqual([]);
    });
  });

  it('assigns and unassigns labels in the same update', async () => {
    await startBulkEdit();
    await checkItem(UNLABELLED_ISSUE_ID);
    await checkItem(LABELLED_ISSUE_ID);
    await addLabels(['Doing']);
    await removeLabels(['To Do']);
    useAfterUpdateFixture('AFTER_ADD_AND_REMOVE');
    await updateSelected();

    await waitForAssertion(() => {
      expect(findLabelChips(UNLABELLED_ISSUE_ID)).toEqual(['Doing']);
      expect(findLabelChips(LABELLED_ISSUE_ID)).toEqual(['Doing']);
    });
  });
});
