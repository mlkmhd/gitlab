import { computed, ref } from 'vue';
import { defineStore } from 'pinia';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_GONE } from '~/lib/utils/http_status';
import { useDiffDiscussions } from '~/rapid_diffs/stores/diff_discussions';
import { useDiffsView } from '~/rapid_diffs/stores/diffs_view';

export const useCommitDiffDiscussions = defineStore('commitDiffDiscussions', () => {
  const diffDiscussions = useDiffDiscussions();
  const endpoint = ref('');

  function setDiscussionsEndpoint(url) {
    endpoint.value = url;
  }

  const timelineDiscussions = computed(() => {
    return diffDiscussions.discussionsWithForms.filter(
      (discussion) => !discussion.isForm && !discussion.diff_discussion,
    );
  });

  // A note made only of quick actions is applied but not saved, so the response has no
  // discussion; the actions return quick_actions_status so the caller can show it
  async function createNewDiscussion(noteData) {
    const { data } = await axios.post(endpoint.value, { note: noteData });
    if (data.discussion) diffDiscussions.addDiscussion(data.discussion);
    return data.quick_actions_status;
  }

  async function createImageDiscussion({ position, noteBody }) {
    return createNewDiscussion({ note: noteBody, position });
  }

  async function createLineDiscussion({ discussion: formDiscussion, noteBody, showWhitespace }) {
    const resolvedShowWhitespace = showWhitespace ?? useDiffsView().showWhitespace;
    const position = {
      ...formDiscussion.position,
      ignore_whitespace_change: !resolvedShowWhitespace,
    };
    const { data } = await axios.post(endpoint.value, {
      note: { note: noteBody, position },
    });
    if (data.discussion) {
      diffDiscussions.replaceDiscussionForm(formDiscussion, data.discussion);
    } else {
      diffDiscussions.removeNewLineDiscussionForm(formDiscussion);
    }
    return data.quick_actions_status;
  }

  async function replyToDiscussion(discussion, noteText) {
    const { data } = await axios.post(endpoint.value, {
      in_reply_to_discussion_id: discussion.reply_id,
      note: { note: noteText },
    });
    if (data.discussion) diffDiscussions.replaceDiscussion(discussion, data.discussion);
    return data.quick_actions_status;
  }

  async function saveNote(note, noteText) {
    try {
      const {
        data: { note: updatedNote },
      } = await axios.put(note.path, {
        rapid_diffs: true,
        target_id: note.noteable_id,
        note: { note: noteText },
      });
      diffDiscussions.updateNote(updatedNote);
    } catch (error) {
      if (error.response?.status === HTTP_STATUS_GONE) {
        diffDiscussions.deleteNote(note);
        return;
      }
      throw error;
    }
  }

  async function destroyNote(note) {
    await axios.delete(note.path);
    diffDiscussions.deleteNote(note);
  }

  async function toggleAwardOnNote(note, name) {
    await axios.post(note.toggle_award_path, { name });
    diffDiscussions.toggleAward({ note, award: name });
  }

  return {
    setDiscussionsEndpoint,
    createNewDiscussion,
    createImageDiscussion,
    createLineDiscussion,
    replyToDiscussion,
    saveNote,
    destroyNote,
    toggleAwardOnNote,
    setInitialDiscussions: diffDiscussions.setInitialDiscussions,
    replaceDiscussion: diffDiscussions.replaceDiscussion,
    toggleDiscussionReplies: diffDiscussions.toggleDiscussionReplies,
    expandDiscussionReplies: diffDiscussions.expandDiscussionReplies,
    startReplying: diffDiscussions.startReplying,
    stopReplying: diffDiscussions.stopReplying,
    addNote: diffDiscussions.addNote,
    updateNote: diffDiscussions.updateNote,
    updateNoteTextById: diffDiscussions.updateNoteTextById,
    editNote: diffDiscussions.editNote,
    deleteNote: diffDiscussions.deleteNote,
    addDiscussion: diffDiscussions.addDiscussion,
    deleteDiscussion: diffDiscussions.deleteDiscussion,
    setEditingMode: diffDiscussions.setEditingMode,
    requestLastNoteEditing: diffDiscussions.requestLastNoteEditing,
    toggleAward: diffDiscussions.toggleAward,
    addNewLineDiscussionForm: diffDiscussions.addNewLineDiscussionForm,
    replaceDiscussionForm: diffDiscussions.replaceDiscussionForm,
    removeNewLineDiscussionForm: diffDiscussions.removeNewLineDiscussionForm,
    setDiscussionFormText: diffDiscussions.setDiscussionFormText,
    setNewLineDiscussionFormAutofocus: diffDiscussions.setNewLineDiscussionFormAutofocus,
    setFileDiscussionsHidden: diffDiscussions.setFileDiscussionsHidden,
    expandLineDiscussions: diffDiscussions.expandLineDiscussions,
    collapseDiscussion: diffDiscussions.collapseDiscussion,
    expandDiscussion: diffDiscussions.expandDiscussion,
    discussionsWithForms: computed(() => diffDiscussions.discussionsWithForms),
    findDiscussionsForFile: computed(() => diffDiscussions.findDiscussionsForFile),
    findLinePositionsForFile: computed(() => diffDiscussions.findLinePositionsForFile),
    findLineDiscussionsForPosition: computed(() => diffDiscussions.findLineDiscussionsForPosition),
    findAllImageDiscussionsForFile: computed(
      () =>
        ({ oldPath, newPath }) =>
          diffDiscussions.findAllImageDiscussionsForFile(oldPath, newPath),
    ),
    timelineDiscussions,
  };
});
