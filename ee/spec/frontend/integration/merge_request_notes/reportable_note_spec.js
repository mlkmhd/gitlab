import {
  screen,
  waitAndClick,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  diffNote,
  findInNote,
  findNote,
  mountMergeRequestNotesApp,
  normalNote,
} from './test_setup';

describe('Reportable note on merge request', () => {
  beforeEach(async () => {
    await mountMergeRequestNotesApp();
  });

  describe.each`
    type             | note
    ${'normal note'} | ${normalNote}
    ${'diff note'}   | ${diffNote}
  `('on a $type', ({ note }) => {
    const openMoreActions = () =>
      waitAndClick(() => findInNote(note).queryByRole('button', { name: /^More actions/ }));

    beforeEach(async () => {
      await waitForElement(() => findNote(note));
    });

    it('has an edit button', () => {
      expect(findInNote(note).queryByTestId('note-edit-button')).not.toBeNull();
    });

    it('has a delete action', async () => {
      await openMoreActions();

      await waitForAssertion(() => {
        expect(findInNote(note).queryByText('Delete comment')).not.toBeNull();
      });
    });

    describe('when reporting abuse', () => {
      beforeEach(async () => {
        await openMoreActions();
        await waitAndClick(() => findInNote(note).queryByText('Report abuse'));
      });

      it('opens the report form for the note author and note URL', async () => {
        await waitForAssertion(() => {
          expect(screen.queryByTestId('input-user-id')?.value).toBe(String(note.author.id));
        });
        expect(screen.queryByTestId('input-referer').value).toBe(note.noteable_note_url);
      });
    });
  });
});
