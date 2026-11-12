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

// The system-defined "to do" status name, from WorkItems::Statuses::SystemDefined::Status.
const STATUS_NAME = 'To do';

describe.each(['project', 'group'])(
  'Board list management - status lists (%s board)',
  (boardType) => {
    beforeEach(() => {
      mountBoardApp({
        boardType,
        dataset: { statusListsAvailable: 'true', workItemStatusAvailable: 'true' },
      });

      return waitForBoard(DEFAULT_LIST_COUNT);
    });

    it('creates a new column for a system-defined status', async () => {
      await waitAndClick(findNewListButton);
      await waitAndClick(() => findListTypeRadio('Status'));
      await waitAndClick(findValueDropdownToggle);
      await waitForElementToBeNull(findListboxLoader);
      await waitAndClick(() => screen.queryByRole('option', { name: STATUS_NAME }));
      await waitAndClick(findAddToBoardButton);

      await waitForAssertion(() => {
        expect(findBoardLists()).toHaveLength(DEFAULT_LIST_COUNT + 1);
        expect(findListByHeaderText(STATUS_NAME)).not.toBeNull();
      });
    });
  },
);
