import autocompleteUsers from 'test_fixtures/graphql/work_items/integration/workspace_autocomplete_users_search.query.graphql.json';
import currentUserResponse from 'test_fixtures/graphql/work_items/integration/current_user.query.graphql.json';
import * as testHelpers from 'ee_jest/integration/helpers/test_helpers';
import * as workItemsHelpers from 'ee_jest/integration/work_items/test_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { namespaceWorkItemFeatures as namespaceWorkItemFeaturesVariants } from 'ee_jest/integration/work_items/fixture_variants';
import {
  setupWorkItemsListApollo,
  createWorkItemsListRouter,
  setupWorkItemsDrawerHooks,
  mountWorkItemsListApp,
} from '../drawer_shared_test_helpers';

setupWorkItemsListApollo();

const { currentUser } = currentUserResponse.data;
const otherUser = autocompleteUsers.data.namespace.users.find(({ id }) => id !== currentUser.id);

// Assigning and unassigning a picked user is covered by describeDrawerInteractions in
// drawer_shared_test_helpers.js.
describe('Work item assignees widget', () => {
  const router = createWorkItemsListRouter();

  setupWorkItemsDrawerHooks();

  const { findAssigneesWidget } = workItemsHelpers;
  const findOptionNames = () =>
    testHelpers
      .within(findAssigneesWidget())
      .queryAllByRole('option')
      .map((option) => testHelpers.getText(option));
  const findSearchInput = () =>
    findAssigneesWidget()?.querySelector('input[type="search"]') ?? null;
  const findAssignYourself = () =>
    findAssigneesWidget()?.querySelector('[data-testid="assign-self"]') ?? null;

  describe('when the work item has no assignees', () => {
    beforeEach(async () => {
      setQueryVariant(namespaceWorkItemFeaturesVariants).noAssignees();

      mountWorkItemsListApp({ router });

      await testHelpers.waitForElement(workItemsHelpers.findIssueToEdit);
      await workItemsHelpers.selectIssue();
      await testHelpers.waitForElement(findAssigneesWidget);
    });

    // Matching users is the server's job, so the frontend's part is sending the typed name
    // and listing what comes back.
    it('lists the project users and searches by the typed name', async () => {
      await workItemsHelpers.startEditing(findAssigneesWidget);

      await testHelpers.waitForAssertion(() => {
        expect(findOptionNames()).toEqual(
          expect.arrayContaining([
            expect.stringContaining(currentUser.name),
            expect.stringContaining(otherUser.name),
          ]),
        );
      });

      await testHelpers.waitAndSetValue(findSearchInput, otherUser.name);

      await testHelpers.waitForAssertion(() => {
        expect(lastRequestVariables('workspaceAutocompleteUsersSearch')).toMatchObject({
          search: otherUser.name,
        });
      });
    });

    it('assigns the current user from the empty state', async () => {
      await testHelpers.waitAndClick(findAssignYourself);

      await testHelpers.waitForElementToBeNull(findAssignYourself);
      expect(testHelpers.getText(findAssigneesWidget())).toContain(currentUser.name);

      // The widget shows its own selection before the mutation returns, so the list row,
      // which reads the cache, is what proves the server's answer was written.
      await testHelpers.waitForAssertion(() => {
        expect(
          workItemsHelpers.findAssigneeLinks().map((link) => link.getAttribute('href')),
        ).toEqual([currentUser.webPath]);
      });
    });
  });
});
