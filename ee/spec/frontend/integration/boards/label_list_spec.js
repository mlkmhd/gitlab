import {
  screen,
  getText,
  within,
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
  findListByHeaderText,
  findListTypeRadio,
  findListboxLoader,
  waitForBoard,
  DEFAULT_LIST_COUNT,
} from './test_setup';

describe.each(['project', 'group'])(
  'Board list management - label lists (%s board)',
  (boardType) => {
    beforeEach(() => {
      mountBoardApp({ boardType });

      return waitForBoard(DEFAULT_LIST_COUNT);
    });

    const addLabelList = async (labelTitle) => {
      await waitAndClick(findNewListButton);
      await waitAndClick(findValueDropdownToggle);
      await waitForElementToBeNull(findListboxLoader);
      await waitAndClick(() => screen.queryByRole('option', { name: labelTitle }));
      await waitAndClick(findAddToBoardButton);
    };

    it('creates a new column for a label', async () => {
      await addLabelList('Frontend');

      await waitForAssertion(() => {
        expect(findBoardLists()).toHaveLength(DEFAULT_LIST_COUNT + 1);
        expect(findListByHeaderText('Frontend')).not.toBeNull();
      });
    });

    it('shows the issue carrying the label', async () => {
      await addLabelList('Frontend');

      await waitForAssertion(() => {
        const labelList = findListByHeaderText('Frontend');
        expect(within(labelList).queryByTestId('board-card')).not.toBeNull();
        expect(getText(within(labelList).queryByTestId('board-card'))).toContain('Labeled issue');
      });
    });

    it('creates a second column without disturbing the first', async () => {
      await addLabelList('Frontend');
      await waitForAssertion(() => {
        expect(findBoardLists()).toHaveLength(DEFAULT_LIST_COUNT + 1);
      });

      await addLabelList('Backend');
      await waitForAssertion(() => {
        expect(findBoardLists()).toHaveLength(DEFAULT_LIST_COUNT + 2);
        expect(findListByHeaderText('Backend')).not.toBeNull();
      });

      const headers = findBoardLists().map((list) =>
        getText(within(list).queryByTestId('board-list-header')),
      );
      expect(headers).toEqual([
        expect.stringContaining('Open'),
        expect.stringContaining('Frontend'),
        expect.stringContaining('Backend'),
        expect.stringContaining('Closed'),
      ]);
    });

    it('offers no other list types without the licensed list features', async () => {
      await waitAndClick(findNewListButton);
      await waitForAssertion(() => expect(findValueDropdownToggle()).not.toBeNull());

      ['Label', 'Milestone', 'Assignee', 'Iteration', 'Status'].forEach((type) => {
        expect(findListTypeRadio(type)).toBeNull();
      });
    });
  },
);
