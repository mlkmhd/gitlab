import { chunk, memoize, uniq } from 'lodash-es';
import { getCookie, removeCookie } from '~/lib/utils/common_utils';
import { initEmojiMap, getEmojiCategoryMap, getAllEmoji, getEmojisForCategory } from '~/emoji';
import { collapseToPreferredTone, pickerGridNames, userSkinTone } from '~/emoji/skin_tone';
import {
  EMOJIS_PER_ROW,
  EMOJI_ROW_HEIGHT,
  CATEGORY_ROW_HEIGHT,
  FREQUENTLY_USED_KEY,
  FREQUENTLY_USED_EMOJIS_STORAGE_KEY,
} from '../constants';

export const generateCategoryHeight = (emojisLength) =>
  emojisLength * EMOJI_ROW_HEIGHT + CATEGORY_ROW_HEIGHT;

/**
 * Helper function to transition legacy cookie-based emoji storage to localStorage.
 * Sets localStorage to the value of the cookie and removes the cookie.
 */
const swapCookieToLocalStorage = () => {
  const cookieContent = getCookie(FREQUENTLY_USED_EMOJIS_STORAGE_KEY);
  localStorage.setItem(FREQUENTLY_USED_EMOJIS_STORAGE_KEY, cookieContent);
  removeCookie(FREQUENTLY_USED_EMOJIS_STORAGE_KEY);
};

export const getFrequentlyUsedEmojis = async () => {
  let savedEmojis = localStorage.getItem(FREQUENTLY_USED_EMOJIS_STORAGE_KEY);

  if (!savedEmojis) {
    const savedEmojisfromCookie = getCookie(FREQUENTLY_USED_EMOJIS_STORAGE_KEY);

    if (!savedEmojisfromCookie) {
      return null;
    }
    savedEmojis = savedEmojisfromCookie;
    swapCookieToLocalStorage();
  }

  const customEmoji = await getEmojisForCategory('custom');
  const possibleEmojiNames = [...customEmoji.map((e) => e.name), ...getAllEmoji().map((e) => e.n)];

  // Saved names keep the tone they were picked in, so the row is remapped to the current tone on read.
  const emojis = chunk(
    collapseToPreferredTone(
      uniq(savedEmojis.split(',')).filter((name) => possibleEmojiNames.includes(name)),
    ),
    9,
  );

  return {
    frequently_used: {
      emojis,
      top: 0,
      height: generateCategoryHeight(emojis.length),
    },
  };
};

export const addToFrequentlyUsed = (emoji) => {
  const frequentlyUsedEmojis = uniq(
    (
      localStorage.getItem(FREQUENTLY_USED_EMOJIS_STORAGE_KEY) ||
      getCookie(FREQUENTLY_USED_EMOJIS_STORAGE_KEY) ||
      ''
    )
      .split(',')
      .filter((e) => e)
      .concat(emoji),
  );

  localStorage.setItem(FREQUENTLY_USED_EMOJIS_STORAGE_KEY, frequentlyUsedEmojis.join(','));
};

export const hasFrequentlyUsedEmojis = async () => (await getFrequentlyUsedEmojis()) !== null;

// Memoised per skin tone, so changing the preference rebuilds the grid once.
export const getEmojiCategories = memoize(
  async () => {
    await initEmojiMap();

    const categories = await getEmojiCategoryMap();
    const frequentlyUsedEmojis = await getFrequentlyUsedEmojis();
    let top = frequentlyUsedEmojis
      ? frequentlyUsedEmojis.frequently_used.top + frequentlyUsedEmojis.frequently_used.height
      : 0;

    return Object.freeze(
      Object.keys(categories)
        .filter((c) => c !== FREQUENTLY_USED_KEY && categories[c].length)
        .reduce((acc, category) => {
          const emojis = chunk(pickerGridNames(categories[category]), EMOJIS_PER_ROW);
          const height = generateCategoryHeight(emojis.length);
          const newAcc = {
            ...acc,
            [category]: { emojis, height, top },
          };
          top += height;

          return newAcc;
        }, frequentlyUsedEmojis || {}),
    );
  },
  () => userSkinTone(),
);
