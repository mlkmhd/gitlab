import { pinia } from '~/pinia/instance';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import { setupNotesState } from '~/mr_notes/init_mr_notes';
import NotesApp from '~/notes/components/notes_app.vue';
import { useNotes } from '~/notes/store/legacy_notes';
import { getNotesFilterData } from '~/notes/utils/get_notes_filter_data';
import { fullMount, within } from 'ee_jest/integration/helpers/test_helpers';
import { discussions, discussionsRootDataset as dataset } from './rest_endpoints';

const notes = discussions.flatMap((discussion) => discussion.notes);

export const diffNote = notes.find((note) => note.type === 'DiffNote');
export const normalNote = notes.find((note) => note.type !== 'DiffNote');

// Mirrors app/assets/javascripts/mr_notes/init_notes.js, fed the dataset the MR page renders.
export async function mountMergeRequestNotesApp() {
  const notesStore = useNotes(pinia);

  notesStore.$reset();
  setupNotesState(dataset);

  const wrapper = fullMount(NotesApp, {
    pinia,
    apolloProvider,
    provide: { reportAbusePath: dataset.reportAbusePath, mrFilter: true },
    propsData: {
      noteableData: notesStore.noteableData,
      notesData: notesStore.notesData,
      shouldShow: true,
      ...getNotesFilterData({ dataset }),
    },
  });

  await notesStore.fetchNotes();

  return wrapper;
}

export const findNote = (note) => document.getElementById(`note_${note.id}`);

export const findInNote = (note) => within(findNote(note));
