import {
  getMutation,
  optimisticAwardUpdate,
  getNewCustomEmojiPath,
} from '~/work_items/notes/award_utils';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import mockApollo from 'helpers/mock_apollo_helper';
import { findNotesWidget } from '~/work_items/utils';
import workItemNotesByIidQuery from '~/work_items/graphql/notes/work_item_notes_by_iid.query.graphql';
import workItemAwardEmojiQuery from '~/work_items/graphql/award_emoji.query.graphql';
import addAwardEmojiMutation from '~/work_items/graphql/notes/work_item_note_add_award_emoji.mutation.graphql';
import removeAwardEmojiMutation from '~/work_items/graphql/notes/work_item_note_remove_award_emoji.mutation.graphql';
import {
  mockAwardEmojiThumbsUp,
  mockAwardEmojiThumbsDown,
  mockWorkItemNotesResponseWithComments,
  withNotesFeatures,
} from 'ee_else_ce_jest/work_items/mock_data';

function getWorkItem(data) {
  return data.namespace.workItem;
}
function getFirstNote(workItem) {
  return findNotesWidget(workItem).discussions.nodes[0].notes.nodes[0];
}

describe('Work item note award utils', () => {
  const workItem = getWorkItem(mockWorkItemNotesResponseWithComments().data);
  const firstNote = getFirstNote(workItem);
  const fullPath = 'test-project-path';
  const workItemIid = workItem.iid;
  const currentUserId = getIdFromGraphQLId(mockAwardEmojiThumbsDown.user.id);

  beforeEach(() => {
    window.gon = { current_user_id: currentUserId, current_user_fullname: 'root' };
  });

  describe('getMutation', () => {
    it('returns remove mutation when user has already awarded award', () => {
      const note = firstNote;
      const { name } = mockAwardEmojiThumbsDown;

      expect(getMutation({ note, name })).toEqual({
        mutation: removeAwardEmojiMutation,
        mutationName: 'awardEmojiRemove',
        errorMessage: 'Failed to remove emoji. Please try again',
      });
    });

    it('returns remove mutation when user has not already awarded award', () => {
      const note = {};
      const { name } = mockAwardEmojiThumbsUp;

      expect(getMutation({ note, name })).toEqual({
        mutation: addAwardEmojiMutation,
        mutationName: 'awardEmojiAdd',
        errorMessage: 'Failed to add emoji. Please try again',
      });
    });
  });

  describe('optimisticAwardUpdate', () => {
    let apolloProvider;
    beforeEach(() => {
      apolloProvider = mockApollo();

      apolloProvider.clients.defaultClient.writeQuery({
        query: workItemNotesByIidQuery,
        variables: { fullPath, iid: workItemIid, useWorkItemFeatures: true },
        ...withNotesFeatures(mockWorkItemNotesResponseWithComments()),
      });
    });

    it('adds new emoji to cache', () => {
      const note = firstNote;
      const { name } = mockAwardEmojiThumbsUp;

      const updateFn = optimisticAwardUpdate({ note, name, fullPath, workItemIid });

      updateFn(apolloProvider.clients.defaultClient.cache);

      const updatedResult = apolloProvider.clients.defaultClient.readQuery({
        query: workItemNotesByIidQuery,
        variables: { fullPath, iid: workItemIid, useWorkItemFeatures: true },
      });

      const updatedWorkItem = getWorkItem(updatedResult);
      const updatedNote = getFirstNote(updatedWorkItem);

      expect(updatedNote.awardEmoji.nodes).toEqual([
        mockAwardEmojiThumbsDown,
        mockAwardEmojiThumbsUp,
      ]);
    });

    it("drops the user's other tones of the emoji when a tone is added with the preference on", () => {
      window.gon.emoji_skin_tone = 'medium';
      const note = firstNote;
      const name = 'thumbsdown_tone3';

      const updateFn = optimisticAwardUpdate({ note, name, fullPath, workItemIid });

      updateFn(apolloProvider.clients.defaultClient.cache);

      const updatedResult = apolloProvider.clients.defaultClient.readQuery({
        query: workItemNotesByIidQuery,
        variables: { fullPath, iid: workItemIid, useWorkItemFeatures: true },
      });

      expect(getFirstNote(getWorkItem(updatedResult)).awardEmoji.nodes).toEqual([
        {
          ...mockAwardEmojiThumbsDown,
          name,
          user: { ...mockAwardEmojiThumbsDown.user, name: 'root' },
        },
      ]);
    });

    it("doesn't add duplicate new emoji to cache", () => {
      const note = firstNote;
      const { name } = mockAwardEmojiThumbsUp;

      const updateFn = optimisticAwardUpdate({ note, name, fullPath, workItemIid });

      // call update twice to simulate two identical optimistic updates
      updateFn(apolloProvider.clients.defaultClient.cache);
      updateFn(apolloProvider.clients.defaultClient.cache);

      const updatedResult = apolloProvider.clients.defaultClient.readQuery({
        query: workItemNotesByIidQuery,
        variables: { fullPath, iid: workItemIid, useWorkItemFeatures: true },
      });

      const updatedWorkItem = getWorkItem(updatedResult);
      const updatedNote = getFirstNote(updatedWorkItem);

      expect(updatedNote.awardEmoji.nodes).toEqual([
        mockAwardEmojiThumbsDown,
        mockAwardEmojiThumbsUp,
      ]);
    });

    it('removes existing emoji from cache', () => {
      const note = firstNote;
      const { name } = mockAwardEmojiThumbsDown;

      const updateFn = optimisticAwardUpdate({ note, name, fullPath, workItemIid });

      updateFn(apolloProvider.clients.defaultClient.cache);

      const updatedResult = apolloProvider.clients.defaultClient.readQuery({
        query: workItemNotesByIidQuery,
        variables: { fullPath, iid: workItemIid, useWorkItemFeatures: true },
      });

      const updatedWorkItem = getWorkItem(updatedResult);
      const updatedNote = getFirstNote(updatedWorkItem);

      expect(updatedNote.awardEmoji.nodes).toEqual([]);
    });

    it('calls cache updateQuery', () => {
      const note = firstNote;
      const { name } = mockAwardEmojiThumbsUp;
      const cacheSpy = { updateQuery: jest.fn() };

      optimisticAwardUpdate({ note, name, fullPath, workItemIid })(cacheSpy);

      expect(cacheSpy.updateQuery).toHaveBeenCalledWith(
        {
          query: workItemNotesByIidQuery,
          variables: { fullPath, iid: workItemIid, useWorkItemFeatures: true },
        },
        expect.any(Function),
      );
    });
  });

  describe('getNewCustomEmojiPath', () => {
    const newCustomEmojiPath = '/groups/gitlab-org/-/custom_emoji/new';
    const mockCache = {
      readQuery: jest.fn().mockReturnValue({
        namespace: {
          workItem: {
            id: 'gid://gitlab/WorkItem/1',
            features: { awardEmoji: { newCustomEmojiPath } },
          },
        },
      }),
    };
    let result;

    beforeEach(() => {
      result = getNewCustomEmojiPath({ cache: mockCache, fullPath, workItemIid });
    });

    it('reads the query with useWorkItemFeatures', () => {
      expect(mockCache.readQuery).toHaveBeenCalledWith({
        query: workItemAwardEmojiQuery,
        variables: { fullPath, iid: workItemIid, pageSize: 1, useWorkItemFeatures: true },
      });
    });

    it('returns newCustomEmojiPath from features', () => {
      expect(result).toBe(newCustomEmojiPath);
    });
  });
});
