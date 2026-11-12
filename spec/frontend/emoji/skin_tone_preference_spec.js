import { createAlert } from '~/alert';
import createApolloClient from '~/lib/graphql';
import { clearPageSingleton } from '~/lib/utils/page_singleton';
import { getEmojiCategories } from '~/emoji/components/utils';
import updateEmojiSkinToneMutation from '~/emoji/queries/update_emoji_skin_tone.mutation.graphql';
import { updateSkinTonePreference } from '~/emoji/skin_tone_preference';

jest.mock('~/alert');
jest.mock('~/lib/graphql');

describe('updateSkinTonePreference', () => {
  const mutate = jest.fn();

  const successResponse = {
    data: { userPreferencesUpdate: { errors: [], userPreferences: { emojiSkinTone: 'MEDIUM' } } },
  };

  beforeEach(() => {
    window.gon = { emoji_skin_tone: 'light' };
    clearPageSingleton('emoji-skin-tone-requests');
    createApolloClient.mockReturnValue({ mutate });
    jest.spyOn(getEmojiCategories.cache, 'clear');
  });

  it('applies the tone to gon, drops the picker cache and saves the preference', async () => {
    mutate.mockResolvedValue(successResponse);

    const promise = updateSkinTonePreference('medium');

    expect(window.gon.emoji_skin_tone).toBe('medium');
    expect(getEmojiCategories.cache.clear).toHaveBeenCalled();

    await expect(promise).resolves.toBe('medium');
    expect(mutate).toHaveBeenCalledWith({
      mutation: updateEmojiSkinToneMutation,
      variables: { emojiSkinTone: 'MEDIUM' },
    });
    expect(createAlert).not.toHaveBeenCalled();
  });

  it('restores the previous tone and shows an alert when the request fails', async () => {
    const error = new Error('network');
    mutate.mockRejectedValue(error);

    await expect(updateSkinTonePreference('medium')).resolves.toBe('light');

    expect(window.gon.emoji_skin_tone).toBe('light');
    expect(createAlert).toHaveBeenCalledWith({
      message: 'Failed to save your default skin tone. Please try again.',
      error,
      captureError: true,
    });
  });

  it('restores the previous tone when the mutation returns errors', async () => {
    mutate.mockResolvedValue({
      data: { userPreferencesUpdate: { errors: ['nope'], userPreferences: null } },
    });

    await expect(updateSkinTonePreference('medium')).resolves.toBe('light');

    expect(window.gon.emoji_skin_tone).toBe('light');
    expect(createAlert).toHaveBeenCalledWith(expect.objectContaining({ error: new Error('nope') }));
  });

  describe('when a newer request overtakes one still in flight', () => {
    const darkResponse = {
      data: { userPreferencesUpdate: { errors: [], userPreferences: { emojiSkinTone: 'DARK' } } },
    };
    const deferred = () => {
      const result = {};
      result.promise = new Promise((resolve, reject) => {
        Object.assign(result, { resolve, reject });
      });
      return result;
    };
    let first;
    let second;

    beforeEach(() => {
      first = deferred();
      second = deferred();
      mutate.mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);
    });

    it('keeps the newer tone when the earlier request succeeds last', async () => {
      const earlier = updateSkinTonePreference('medium');
      const later = updateSkinTonePreference('dark');

      second.resolve(darkResponse);
      await expect(later).resolves.toBe('dark');

      first.resolve(successResponse);
      await expect(earlier).resolves.toBe('dark');
      expect(window.gon.emoji_skin_tone).toBe('dark');
    });

    it('keeps the newer tone when the earlier request fails last', async () => {
      const earlier = updateSkinTonePreference('medium');
      const later = updateSkinTonePreference('dark');

      second.resolve(darkResponse);
      await expect(later).resolves.toBe('dark');

      first.reject(new Error('network'));
      await expect(earlier).resolves.toBe('dark');
      expect(window.gon.emoji_skin_tone).toBe('dark');
      expect(createAlert).not.toHaveBeenCalled();
    });

    it('restores the tone the newer request replaced when only it fails', async () => {
      const earlier = updateSkinTonePreference('medium');
      const later = updateSkinTonePreference('dark');

      second.reject(new Error('network'));
      await expect(later).resolves.toBe('medium');

      first.resolve(successResponse);
      await expect(earlier).resolves.toBe('medium');
      expect(window.gon.emoji_skin_tone).toBe('medium');
    });

    it('restores the tone the server holds when both requests fail', async () => {
      const earlier = updateSkinTonePreference('medium');
      const later = updateSkinTonePreference('dark');

      second.reject(new Error('network'));
      await expect(later).resolves.toBe('medium');

      first.reject(new Error('network'));
      await expect(earlier).resolves.toBe('light');
      expect(window.gon.emoji_skin_tone).toBe('light');
      expect(createAlert).toHaveBeenCalledTimes(1);
    });
  });
});
