import { createAlert } from '~/alert';
import createApolloClient from '~/lib/graphql';
import { pageSingleton } from '~/lib/utils/page_singleton';
import { s__ } from '~/locale';
import { getEmojiCategories } from './components/utils';
import updateEmojiSkinToneMutation from './queries/update_emoji_skin_tone.mutation.graphql';
import { setUserSkinTone, userSkinTone } from './skin_tone';

// Shared with the copy of this module that a Vue 3 page builds, so one client per page.
const client = () => pageSingleton('emoji-skin-tone-apollo-client', createApolloClient);

// Shared too, so saves made from either copy settle against one history.
const requests = () =>
  pageSingleton('emoji-skin-tone-requests', () => ({
    // The tone the server is known to hold, and the request that saved it.
    saved: userSkinTone(),
    savedBy: 0,
    latest: 0,
    pending: [],
  }));

const applySkinTone = (tone) => {
  if (userSkinTone() === tone) return;

  setUserSkinTone(tone);
  getEmojiCategories.cache.clear();
};

/**
 * Saves the user's default skin tone: `gon` is updated first, so every `~/emoji/skin_tone`
 * helper, the components whose computed properties read them and the picker cache follow at
 * once. Resolves to the tone in effect afterwards.
 * Whenever a request settles, `gon` is set to the tone of the newest request that is still
 * in flight or has succeeded, and to the tone the server last confirmed when there is none,
 * so slow or failed responses can neither undo a newer choice nor leave an unsaved one.
 * Pickers mount in notes, designs, wikis and diffs without an Apollo provider,
 * so the mutation runs on a standalone client.
 */
export const updateSkinTonePreference = async (tone) => {
  const tracker = requests();
  tracker.latest += 1;
  const request = { id: tracker.latest, tone };
  tracker.pending.push(request);
  applySkinTone(tone);

  try {
    const { data } = await client().mutate({
      mutation: updateEmojiSkinToneMutation,
      variables: { emojiSkinTone: tone.toUpperCase() },
    });
    const errors = data?.userPreferencesUpdate?.errors ?? [];

    if (errors.length) throw new Error(errors.join(', '));
    if (request.id > tracker.savedBy) Object.assign(tracker, { saved: tone, savedBy: request.id });
  } catch (error) {
    // A newer request reports its own outcome, so an overtaken failure stays quiet.
    if (request.id === tracker.latest) {
      createAlert({
        message: s__('EmojiSkinTone|Failed to save your default skin tone. Please try again.'),
        error,
        captureError: true,
      });
    }
  } finally {
    tracker.pending = tracker.pending.filter((other) => other !== request);
    const newest = tracker.pending.at(-1);
    applySkinTone(newest && newest.id > tracker.savedBy ? newest.tone : tracker.saved);
  }

  return userSkinTone();
};
