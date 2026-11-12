import workItemNotesByIidFeatures from 'test_fixtures/graphql/work_items/integration/work_item_notes_by_iid_features.query.graphql.json';
import workItemMetadata from 'test_fixtures/graphql/work_items/integration/work_item_metadata.query.graphql.json';
import namespaceWorkItemNonMember from 'test_fixtures/graphql/work_items/integration/namespace_work_item_non_member_features.query.graphql.json';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import * as testHelpers from 'ee_jest/integration/helpers/test_helpers';
import * as workItemsHelpers from 'ee_jest/integration/work_items/test_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  namespaceWorkItemFeatures as namespaceWorkItemFeaturesVariants,
  workItemNotesByIidFeatures as workItemNotesByIidFeaturesVariants,
} from 'ee_jest/integration/work_items/fixture_variants';
import { OTHER_USER_ID } from 'ee_jest/integration/work_items/fixture_variants/work_item_notes_by_iid_features';
import {
  setupWorkItemsListApollo,
  createWorkItemsListRouter,
  setupWorkItemsDrawerHooks,
  mountWorkItemsListApp,
} from '../drawer_shared_test_helpers';

setupWorkItemsListApollo();

const { reportAbuse: REPORT_ABUSE_PATH } = workItemMetadata.data.namespace.linkPaths;

const { url: NOTE_URL } =
  workItemNotesByIidFeatures.data.namespace.workItem.features.notes.discussions.nodes[0].notes
    .nodes[0];
const { webUrl: WORK_ITEM_URL, author: WORK_ITEM_AUTHOR } =
  namespaceWorkItemNonMember.data.namespace.workItem;

describe('Report abuse on a work item', () => {
  const router = createWorkItemsListRouter();

  setupWorkItemsDrawerHooks();

  // Dropdown items emit `action` from their inner button, not the `li` carrying the test ID.
  const findDropdownItemButton = (testId) =>
    workItemsHelpers.findInDrawer(testId)?.querySelector('button') ?? null;
  const findWorkItemMoreActions = () => findDropdownItemButton('work-item-actions-dropdown');
  const findNoteMoreActions = () => {
    const note = workItemsHelpers.findInDrawer('note-wrapper');
    return note ? testHelpers.within(note).queryByRole('button', { name: /^More actions/ }) : null;
  };

  const openDrawerAndClick = async (findMoreActions) => {
    mountWorkItemsListApp({ router });
    await testHelpers.waitForSetup(() => {
      expect(workItemsHelpers.findIssueToEdit()).not.toBeNull();
    });
    workItemsHelpers.clickIssue();
    await testHelpers.waitForSetup(() => {
      expect(findMoreActions()).not.toBeNull();
    });
    findMoreActions().click();
  };

  const expectReportFormFor = async ({ userId, url }) => {
    await testHelpers.waitForAssertion(() => {
      expect(testHelpers.screen.queryByTestId('input-user-id')?.value).toBe(
        String(getIdFromGraphQLId(userId)),
      );
    });
    expect(testHelpers.screen.queryByTestId('input-referer').value).toBe(url);
    expect(
      testHelpers.screen.queryByTestId('input-user-id').closest('form').getAttribute('action'),
    ).toBe(REPORT_ABUSE_PATH);
  };

  describe('when the work item is by another user', () => {
    beforeEach(async () => {
      setQueryVariant(namespaceWorkItemFeaturesVariants).nonMember();
      await openDrawerAndClick(findWorkItemMoreActions);
    });

    describe('when reporting abuse', () => {
      beforeEach(async () => {
        await testHelpers.waitAndClick(() => findDropdownItemButton('report-abuse-action'));
      });

      it('opens the report form for the work item author and work item URL', async () => {
        await expectReportFormFor({ userId: WORK_ITEM_AUTHOR.id, url: WORK_ITEM_URL });
      });
    });
  });

  describe('when the comment is by another user', () => {
    beforeEach(async () => {
      setQueryVariant(workItemNotesByIidFeaturesVariants).postedByOtherUser();
      await openDrawerAndClick(findNoteMoreActions);
    });

    describe('when reporting abuse', () => {
      beforeEach(async () => {
        await testHelpers.waitAndClick(() => findDropdownItemButton('abuse-note-action'));
      });

      it('opens the report form for the note author and note URL', async () => {
        await expectReportFormFor({ userId: OTHER_USER_ID, url: NOTE_URL });
      });
    });
  });
});
