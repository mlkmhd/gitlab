import { initEmojiMock } from 'helpers/emoji';
import {
  getFrequentlyUsedEmojis,
  addToFrequentlyUsed,
  getEmojiCategories,
} from '~/emoji/components/utils';
import { EMOJI_THUMBS_UP, EMOJI_THUMBS_DOWN } from '~/emoji/constants';

const PEOPLE = 'People & Body';
const MIXED = 'couple_with_heart_man_man_dark_skin_tone_light_skin_tone';
const UNMAPPED = 'man_in_tuxedo_dark_skin_tone';
const tonedEmojiData = [
  { n: 'thumbsup', e: '👍', c: PEOPLE, d: 'thumbs up', u: '6.0' },
  { n: 'thumbsup_tone1', e: '👍🏻', c: PEOPLE, d: 'thumbs up: light skin tone', u: '8.0' },
  { n: 'thumbsup_tone3', e: '👍🏽', c: PEOPLE, d: 'thumbs up: medium skin tone', u: '8.0' },
  { n: 'thumbsdown', e: '👎', c: PEOPLE, d: 'thumbs down', u: '6.0' },
  { n: 'thumbsdown_tone3', e: '👎🏽', c: PEOPLE, d: 'thumbs down: medium skin tone', u: '8.0' },
  { n: UNMAPPED, e: '🤵🏿‍♂️', c: PEOPLE, d: 'man in tuxedo: dark skin tone', u: '13.0' },
  { n: MIXED, e: '👨🏿‍❤️‍👨🏻', c: PEOPLE, d: 'couple with heart', u: '13.1' },
  { n: 'rocket', e: '🚀', c: 'Travel & Places', d: 'rocket', u: '6.0' },
];

const { getItem, setItem } = Storage.prototype;
const restoreStorage = () => {
  Storage.prototype.getItem = getItem;
  Storage.prototype.setItem = setItem;
};

describe('getFrequentlyUsedEmojis', () => {
  beforeAll(async () => {
    await initEmojiMock();
  });

  it('returns null when no saved emojis set', async () => {
    Storage.prototype.setItem = jest.fn();

    expect(await getFrequentlyUsedEmojis()).toBe(null);
  });

  it('returns frequently used emojis object', async () => {
    Storage.prototype.getItem = jest.fn(() => `${EMOJI_THUMBS_UP},${EMOJI_THUMBS_DOWN}`);

    const frequentlyUsed = await getFrequentlyUsedEmojis();

    expect(frequentlyUsed).toEqual({
      frequently_used: {
        emojis: [[EMOJI_THUMBS_UP, EMOJI_THUMBS_DOWN]],
        top: 0,
        height: 73,
      },
    });
  });

  it('only returns frequently used emojis that are in the possible emoji set', async () => {
    Storage.prototype.getItem = jest.fn(() => `${EMOJI_THUMBS_UP},${EMOJI_THUMBS_DOWN},ack`);

    const frequentlyUsed = await getFrequentlyUsedEmojis();

    expect(frequentlyUsed).toEqual({
      frequently_used: {
        emojis: [[EMOJI_THUMBS_UP, EMOJI_THUMBS_DOWN]],
        top: 0,
        height: 73,
      },
    });
  });
});

describe('addToFrequentlyUsed', () => {
  it('sets cookie value', () => {
    Storage.prototype.getItem = jest.fn(() => null);

    addToFrequentlyUsed(EMOJI_THUMBS_UP);

    expect(localStorage.setItem).toHaveBeenCalledWith('frequently_used_emojis', EMOJI_THUMBS_UP);
  });

  it('sets cookie value to include previously set cookie value', () => {
    Storage.prototype.getItem = jest.fn(() => EMOJI_THUMBS_DOWN);

    addToFrequentlyUsed(EMOJI_THUMBS_UP);

    expect(localStorage.setItem).toHaveBeenCalledWith(
      'frequently_used_emojis',
      `${EMOJI_THUMBS_DOWN},${EMOJI_THUMBS_UP}`,
    );
  });

  it('sets cookie value with uniq values', () => {
    Storage.prototype.getItem = jest.fn(() => EMOJI_THUMBS_UP);

    addToFrequentlyUsed(EMOJI_THUMBS_UP);

    expect(localStorage.setItem).toHaveBeenCalledWith('frequently_used_emojis', EMOJI_THUMBS_UP);
  });
});

// The tests above replace the Storage prototype; these need the real one to load the emoji mock.
describe('getFrequentlyUsedEmojis with the skin tone preference', () => {
  beforeAll(async () => {
    restoreStorage();
    await initEmojiMock(tonedEmojiData);
  });

  it('remaps the saved names to the current tone and folds duplicates', async () => {
    window.gon = { emoji_skin_tone: 'medium' };
    localStorage.setItem('frequently_used_emojis', 'thumbsup_tone1,rocket,thumbsup,thumbsdown');

    const frequentlyUsed = await getFrequentlyUsedEmojis();

    expect(frequentlyUsed.frequently_used.emojis).toEqual([
      ['thumbsup_tone3', 'rocket', 'thumbsdown_tone3'],
    ]);
  });
});

describe('getEmojiCategories', () => {
  beforeAll(async () => {
    restoreStorage();
    await initEmojiMock(tonedEmojiData);
  });

  beforeEach(() => {
    localStorage.clear();
    getEmojiCategories.cache.clear();
  });

  it('lists every name of a category without the preference', async () => {
    const categories = await getEmojiCategories();

    expect(categories[PEOPLE].emojis).toEqual([
      [
        'thumbsup',
        'thumbsup_tone1',
        'thumbsup_tone3',
        'thumbsdown',
        'thumbsdown_tone3',
        UNMAPPED,
        MIXED,
      ],
    ]);
  });

  it('shows one tile per emoji in the preferred tone and leaves two-tone and unmapped names to search', async () => {
    window.gon = { emoji_skin_tone: 'medium' };

    const categories = await getEmojiCategories();

    expect(categories[PEOPLE].emojis).toEqual([['thumbsup_tone3', 'thumbsdown_tone3']]);
    expect(categories['Travel & Places'].emojis).toEqual([['rocket']]);
  });

  it('is memoised per tone', async () => {
    window.gon = { emoji_skin_tone: 'medium' };
    const medium = await getEmojiCategories();

    window.gon = { emoji_skin_tone: 'dark' };
    const dark = await getEmojiCategories();

    window.gon = { emoji_skin_tone: 'medium' };

    expect(dark).not.toBe(medium);
    expect(dark[PEOPLE].emojis).toEqual([['thumbsup_tone5', 'thumbsdown_tone5']]);
    expect(await getEmojiCategories()).toBe(medium);
  });
});
