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

describe.each(['project', 'group'])(
  'Board list management - milestone lists (%s board)',
  (boardType) => {
    beforeEach(() => {
      mountBoardApp({ boardType, dataset: { milestoneListsAvailable: 'true' } });

      return waitForBoard(DEFAULT_LIST_COUNT);
    });

    it('creates a new column for a milestone', async () => {
      await waitAndClick(findNewListButton);
      await waitAndClick(() => findListTypeRadio('Milestone'));
      await waitAndClick(findValueDropdownToggle);
      await waitForElementToBeNull(findListboxLoader);
      await waitAndClick(() => screen.queryByRole('option', { name: '16.0' }));
      await waitAndClick(findAddToBoardButton);

      await waitForAssertion(() => {
        expect(findBoardLists()).toHaveLength(DEFAULT_LIST_COUNT + 1);
        expect(findListByHeaderText('16.0')).not.toBeNull();
      });
    });
  },
);
