import namespaceWorkItemFeatures from 'test_fixtures/graphql/work_items/integration/namespace_work_item_features.query.graphql.json';
import {
  expectGraphQLCalls,
  lastRequestVariables,
  snapshotRequests,
} from 'ee_jest/integration/core/operation_helpers';
import {
  getText,
  waitAndClick,
  waitAndSetValue,
  waitForAssertion,
  waitForElement,
  waitForElementToBeNull,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  findAddTreeChildToggle,
  findAddTreeForm,
  findInDrawer,
  findIssueToEdit,
  findWorkItemTree,
  selectIssue,
} from 'ee_jest/integration/work_items/test_helpers';
import {
  createWorkItem,
  workItemTreeQueryFeatures,
} from 'ee_jest/integration/work_items/fixture_variants';
import {
  setupWorkItemsListApollo,
  createWorkItemsListRouter,
  setupWorkItemsDrawerHooks,
  mountWorkItemsListApp,
} from '../drawer_shared_test_helpers';
import { setQueryVariant, setUserSession } from '../../helpers/setup_utils';

setupWorkItemsListApollo();

// The drawer opens this work item, so a child created from its tree carries its id.
const PARENT_ID = namespaceWorkItemFeatures.data.namespace.workItem.id;

// Migrated from spec/features/work_items/detail/work_item_children_spec.rb.
//
// Drag-and-drop reorder stays in Capybara: jsdom has no layout or coordinate system, so
// SortableJS cannot be driven here. `setUserSession(false)` renders the non-draggable
// tree, which is what makes the rows visible under Vue 3.
describe('Work item children integration test', () => {
  const router = createWorkItemsListRouter();

  setupWorkItemsDrawerHooks();

  const openTree = async () => {
    setQueryVariant(workItemTreeQueryFeatures).withChildren();

    mountWorkItemsListApp({ router });
    await waitForElement(findIssueToEdit);

    setUserSession(false);
    await selectIssue();

    return waitForElement(findWorkItemTree);
  };

  // Opens one of the add-child options from the split button's disclosure dropdown.
  const openAddChildForm = async (optionText) => {
    await waitAndClick(findAddTreeChildToggle);
    await waitAndClick(() => within(findWorkItemTree()).queryByText(optionText));

    return waitForElement(findAddTreeForm);
  };

  describe('when the work item has children', () => {
    it('shows each child with its labels, milestone and assignee', async () => {
      const tree = await openTree();

      await waitForAssertion(() => {
        const treeText = getText(tree);

        expect(treeText).toContain('Visible child task');
        expect(treeText).toContain('To Do');
        expect(treeText).toContain('v1.0');
        expect(treeText).toContain('Assignable User');
      });
    });
  });

  describe('when the add-child form is opened', () => {
    it('closes again on Cancel', async () => {
      await openTree();

      expect(findAddTreeForm()).toBe(null);

      await openAddChildForm('New task');

      await waitAndClick(() => within(findAddTreeForm()).queryByRole('button', { name: 'Cancel' }));

      await waitForElementToBeNull(findAddTreeForm);
    });
  });

  describe('when a new child is created from the tree', () => {
    const findCreateButton = () =>
      within(findAddTreeForm()).queryByRole('button', { name: 'Create task' });

    let baselineRequests;

    beforeEach(async () => {
      await openTree();
      // The tree's create form sends a parent, so the response has to be the task recording.
      setQueryVariant(createWorkItem).childTask();

      await openAddChildForm('New task');

      const findTitleInput = () =>
        findInDrawer('work-items-create-form-group')?.querySelector('input') ?? null;
      await waitAndSetValue(findTitleInput, 'Child 1');

      // The Create button stays disabled until the title binding lands, so wait on it
      // rather than on the value being set.
      await waitForAssertion(() => {
        expect(findCreateButton().disabled).toBe(false);
      });

      baselineRequests = snapshotRequests();
      findCreateButton().click();

      await waitForAssertion(() => {
        expectGraphQLCalls(baselineRequests, { expect: ['createWorkItem'], forbid: [] });
      });
    });

    it('sends the typed title and the open work item as the parent', () => {
      const { input } = lastRequestVariables('createWorkItem');

      expect(input.title).toBe('Child 1');
      expect(input.hierarchyWidget.parentId).toBe(PARENT_ID);
    });

    it('shows the created child in the tree', async () => {
      // The row renders the recorded response, so the title here is the fixture's, not the
      // one typed above. What we typed is asserted on the request instead.
      await waitForAssertion(() => {
        expect(getText(findWorkItemTree())).toContain('New child task');
      });
    });

    it('writes the child into the cached tree instead of refetching it', async () => {
      await waitForAssertion(() => {
        expect(getText(findWorkItemTree())).toContain('New child task');
      });
      // A cache-miss refetch is issued one turn after the mutation resolves, so the forbid
      // check has to let the task queue drain or it passes while that refetch is pending.
      await new Promise((resolve) => {
        setTimeout(resolve, 0);
      });

      // Only the tree is updated in place. The list is evicted on purpose, because
      // `planning_view.vue` binds `@add-child` to `refetchItems`.
      expectGraphQLCalls(baselineRequests, {
        expect: ['createWorkItem'],
        forbid: ['workItemTreeQuery'],
      });
    });
  });
});
