import {
  waitAndClick,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  findIssueToEdit,
  findTodosToggleWithPending,
  selectIssue,
} from 'ee_jest/integration/work_items/test_helpers';
import { snapshotRequests } from 'ee_jest/integration/core/operation_helpers';
import {
  setupWorkItemsListApollo,
  createWorkItemsListRouter,
  setupWorkItemsDrawerHooks,
  describeNoRefetchOnMutation,
  mountWorkItemsListApp,
} from '../drawer_shared_test_helpers';

setupWorkItemsListApollo();

describe('Work item to-do toggle integration test', () => {
  const router = createWorkItemsListRouter();

  setupWorkItemsDrawerHooks();

  // The toggle is one button that relabels itself.
  const findPendingToggle = findTodosToggleWithPending(true);
  const findEmptyToggle = findTodosToggleWithPending(false);

  // The cache write relabels the toggle a few microtasks before the mutation settles, and the
  // toggle ignores clicks until then, so a click right after a relabel can be dropped. Retrying
  // is safe: clicks during an update are ignored, so only one mutation goes out.
  const clickUntilPending = (pending) =>
    waitForAssertion(() => {
      findTodosToggleWithPending(!pending)()?.click();
      expect(findTodosToggleWithPending(pending)()).not.toBe(null);
    });

  const markTodoDoneFromDrawer = async () => {
    await selectIssue();

    // The detail query seeds one pending to-do, so the toggle renders in
    // "mark as done" state once the drawer is open.
    await waitForElement(findPendingToggle);

    // Snapshot once the drawer detail query has resolved, just before the
    // mark-as-done mutation fires.
    const baseline = snapshotRequests();

    await waitAndClick(findPendingToggle);

    return baseline;
  };

  const addTodoFromDrawer = async () => {
    await selectIssue();
    await waitForElement(findPendingToggle);

    // Clear the seeded to-do so the next click takes the add path.
    await waitAndClick(findPendingToggle);
    await waitForElement(findEmptyToggle);

    const baseline = snapshotRequests();

    await clickUntilPending(true);

    return baseline;
  };

  describe('when the to-do is toggled from the drawer', () => {
    it('marks it done and adds it back', async () => {
      mountWorkItemsListApp({ router });
      await waitForElement(findIssueToEdit);
      await selectIssue();

      // The detail query seeds one pending to-do, so the round trip starts from there.
      await waitAndClick(findPendingToggle);
      await waitForAssertion(() => {
        expect(findTodosToggleWithPending(false)()).not.toBe(null);
      });

      await clickUntilPending(true);
    });
  });

  // Marking the to-do done must update the Apollo cache in place via the
  // workItemUpdateCurrentUserTodos mutation and must NOT trigger a refetch of the
  // namespaceWorkItem detail query. On the features path, a mismatch between the
  // mutation's currentUserTodos selection and the query fragment (e.g. a missing
  // `state: pending` argument) writes to a different cache slot and causes a refetch.
  describeNoRefetchOnMutation({
    router,
    description: 'marks the to-do done without refetching the work item',
    perform: markTodoDoneFromDrawer,
    expectOps: ['workItemUpdateCurrentUserTodos'],
    forbidOps: ['namespaceWorkItem'],
  });

  // Adding a to-do goes through the same mutation with `action: ADD`, so it normalizes the
  // same way. It used to go through `todoCreate`, which returns a bare Todo and therefore
  // needed a hand-written cache update.
  describeNoRefetchOnMutation({
    router,
    description: 'adds a to-do without refetching the work item',
    perform: addTodoFromDrawer,
    expectOps: ['workItemUpdateCurrentUserTodos'],
    forbidOps: ['namespaceWorkItem'],
  });
});
