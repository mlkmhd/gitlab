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

// The list header shows the cadence title and period, not the iteration title (see
// EE::List#title), so the fixture generator gives the cadence a stable name.
const CADENCE_TITLE = 'Sprint Cadence';

describe.each(['project', 'group'])(
  'Board list management - iteration lists (%s board)',
  (boardType) => {
    beforeEach(() => {
      mountBoardApp({ boardType, dataset: { iterationListsAvailable: 'true' } });

      return waitForBoard(DEFAULT_LIST_COUNT);
    });

    it('creates a new column for an iteration', async () => {
      await waitAndClick(findNewListButton);
      await waitAndClick(() => findListTypeRadio('Iteration'));
      await waitAndClick(findValueDropdownToggle);
      await waitForElementToBeNull(findListboxLoader);
      await waitAndClick(() => screen.queryByRole('option', { name: /Sprint 1/ }));
      await waitAndClick(findAddToBoardButton);

      await waitForAssertion(() => {
        expect(findBoardLists()).toHaveLength(DEFAULT_LIST_COUNT + 1);
        expect(findListByHeaderText(CADENCE_TITLE)).not.toBeNull();
      });
    });
  },
);
