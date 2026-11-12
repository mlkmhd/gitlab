import {
  screen,
  waitAndClick,
  waitForElementToBeNull,
  waitForAssertion,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  mountBoardApp,
  findNewListButton,
  findValueDropdownToggle,
  findAddToBoardButton,
  findBoardLists,
  findListTypeRadio,
  findListByHeaderText,
  findListboxLoader,
  waitForBoard,
  DEFAULT_LIST_COUNT,
} from './test_setup';

// The board owner (maintainer_of/owner_of in the fixture generator) is the assignee the
// dropdown offers; its name is recorded in users_autocomplete_{project,group}.query.graphql.json.
const ASSIGNEE_NAME = 'Board Owner';

describe.each(['project', 'group'])(
  'Board list management - assignee lists (%s board)',
  (boardType) => {
    beforeEach(() => {
      mountBoardApp({ boardType, dataset: { assigneeListsAvailable: 'true' } });

      return waitForBoard(DEFAULT_LIST_COUNT);
    });

    it('creates a new column for an assignee', async () => {
      await waitAndClick(findNewListButton);
      await waitAndClick(() => findListTypeRadio('Assignee'));
      await waitAndClick(findValueDropdownToggle);
      // The dropdown's own search spinner is the readiness signal that the autocomplete
      // request has resolved; without it the option can still be loading when queried.
      await waitForElementToBeNull(findListboxLoader);
      await waitAndClick(() => screen.queryByRole('option', { name: new RegExp(ASSIGNEE_NAME) }));
      await waitAndClick(findAddToBoardButton);

      await waitForAssertion(() => {
        expect(findBoardLists()).toHaveLength(DEFAULT_LIST_COUNT + 1);
        expect(findListByHeaderText(ASSIGNEE_NAME)).not.toBeNull();
      });
    });
  },
);
