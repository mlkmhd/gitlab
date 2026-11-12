import projectMilestonesWithExpired from 'test_fixtures/graphql/work_items/integration/project_milestones_with_expired.query.graphql.json';
import * as testHelpers from 'ee_jest/integration/helpers/test_helpers';
import * as workItemsHelpers from 'ee_jest/integration/work_items/test_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { projectMilestones as projectMilestonesVariants } from 'ee_jest/integration/work_items/fixture_variants';
import {
  setupWorkItemsListApollo,
  createWorkItemsListRouter,
  setupWorkItemsDrawerHooks,
  mountWorkItemsListApp,
} from '../drawer_shared_test_helpers';

setupWorkItemsListApollo();

// The server sorts soonest due first and expired last, so the fixture is already in the order
// the dropdown has to keep. The frontend's part is keeping that order and flagging expiry.
const expectedOptions = projectMilestonesWithExpired.data.namespace.attributes.nodes.map(
  ({ title, expired }) => (expired ? `${title} (expired)` : title),
);

// Selecting, searching and clearing a milestone is covered by describeDrawerInteractions in
// drawer_shared_test_helpers.js.
describe('Work item milestone widget', () => {
  const router = createWorkItemsListRouter();

  setupWorkItemsDrawerHooks();

  const { findMilestoneWidget } = workItemsHelpers;
  const findOptionNames = () =>
    testHelpers
      .within(findMilestoneWidget())
      .queryAllByRole('option')
      .map((option) => testHelpers.getText(option));

  beforeEach(async () => {
    setQueryVariant(projectMilestonesVariants).withExpired();

    mountWorkItemsListApp({ router });

    await testHelpers.waitForElement(workItemsHelpers.findIssueToEdit);
    await workItemsHelpers.selectIssue();
    await testHelpers.waitForElement(findMilestoneWidget);
  });

  it('lists milestones in the order the server returns them and marks expired ones', async () => {
    expect(expectedOptions.some((option) => option.endsWith('(expired)'))).toBe(true);

    await workItemsHelpers.startEditing(findMilestoneWidget);

    await testHelpers.waitForAssertion(() => {
      expect(findOptionNames()).toEqual(expectedOptions);
    });
  });
});
