import { nextTick } from 'vue';
import { shallowMount } from '@vue/test-utils';
import skinTones from 'emojis/skin_tones.json';
import {
  DEFAULT_SKIN_TONE,
  SKIN_TONES,
  baseName,
  collapseToPreferredTone,
  isOtherToneOfSameEmoji,
  isSkinTonePreferenceEnabled,
  pickerGridNames,
  preferredVariant,
  setUserSkinTone,
  userSkinTone,
  variantForTone,
  variantsFor,
  withPreferredTone,
} from '~/emoji/skin_tone';

const MIXED = 'couple_with_heart_man_man_dark_skin_tone_light_skin_tone';
const UNMAPPED = 'man_in_tuxedo_dark_skin_tone';

describe('emoji skin tone helpers', () => {
  describe('userSkinTone', () => {
    it('is null without a preference in gon', () => {
      expect(userSkinTone()).toBe(null);
      expect(isSkinTonePreferenceEnabled()).toBe(false);
    });

    it('returns the preference from gon', () => {
      window.gon = { emoji_skin_tone: 'default' };

      expect(userSkinTone()).toBe('default');
      expect(isSkinTonePreferenceEnabled()).toBe(true);
    });
  });

  describe('baseName', () => {
    it.each`
      name                                                          | base
      ${'thumbsup'}                                                 | ${'thumbsup'}
      ${'thumbsup_tone1'}                                           | ${'thumbsup'}
      ${'thumbsup_tone5'}                                           | ${'thumbsup'}
      ${'people_holding_hands_medium_dark_skin_tone'}               | ${'people_holding_hands'}
      ${'rocket'}                                                   | ${'rocket'}
      ${'man_in_tuxedo_dark_skin_tone'}                             | ${'man_in_tuxedo_dark_skin_tone'}
      ${'couple_with_heart_man_man_dark_skin_tone_light_skin_tone'} | ${'couple_with_heart_man_man_dark_skin_tone_light_skin_tone'}
    `('maps $name to $base', ({ name, base }) => {
      expect(baseName(name)).toBe(base);
    });
  });

  describe('variantsFor', () => {
    it('returns the five tones of an emoji in light to dark order', () => {
      expect(variantsFor('thumbsup')).toEqual([
        'thumbsup_tone1',
        'thumbsup_tone2',
        'thumbsup_tone3',
        'thumbsup_tone4',
        'thumbsup_tone5',
      ]);
    });

    it('returns no tones for an emoji without a tone group', () => {
      expect(variantsFor('rocket')).toEqual([]);
      expect(variantsFor('thumbsup_tone1')).toEqual([]);
    });
  });

  describe('preferredVariant', () => {
    it.each`
      tone              | variant
      ${'default'}      | ${'thumbsup'}
      ${'light'}        | ${'thumbsup_tone1'}
      ${'medium_light'} | ${'thumbsup_tone2'}
      ${'medium'}       | ${'thumbsup_tone3'}
      ${'medium_dark'}  | ${'thumbsup_tone4'}
      ${'dark'}         | ${'thumbsup_tone5'}
    `('returns $variant for the $tone preference', ({ tone, variant }) => {
      window.gon = { emoji_skin_tone: tone };

      expect(preferredVariant('thumbsup')).toBe(variant);
      expect(preferredVariant('thumbsup_tone2')).toBe(variant);
    });

    it('returns the plain name when the emoji has no tone group', () => {
      window.gon = { emoji_skin_tone: 'dark' };

      expect(preferredVariant('rocket')).toBe('rocket');
      expect(preferredVariant('man_in_tuxedo_dark_skin_tone')).toBe('man_in_tuxedo_dark_skin_tone');
    });

    it('returns the plain name without a preference', () => {
      expect(preferredVariant('thumbsup_tone2')).toBe('thumbsup');
    });
  });

  describe('SKIN_TONES', () => {
    it('lists the default tone first and then the fixture tones from light to dark', () => {
      expect(SKIN_TONES).toEqual([
        DEFAULT_SKIN_TONE,
        'light',
        'medium_light',
        'medium',
        'medium_dark',
        'dark',
      ]);
    });
  });

  describe('variantForTone', () => {
    it.each`
      base             | tone              | variant
      ${'raised_hand'} | ${'default'}      | ${'raised_hand'}
      ${'raised_hand'} | ${'light'}        | ${'raised_hand_tone1'}
      ${'raised_hand'} | ${'medium_light'} | ${'raised_hand_tone2'}
      ${'raised_hand'} | ${'medium'}       | ${'raised_hand_tone3'}
      ${'raised_hand'} | ${'medium_dark'}  | ${'raised_hand_tone4'}
      ${'raised_hand'} | ${'dark'}         | ${'raised_hand_tone5'}
      ${'rocket'}      | ${'dark'}         | ${'rocket'}
      ${UNMAPPED}      | ${'light'}        | ${UNMAPPED}
    `('returns $variant for $base in the $tone tone', ({ base, tone, variant }) => {
      expect(variantForTone(base, tone)).toBe(variant);
    });
  });

  describe('withPreferredTone', () => {
    beforeEach(() => {
      window.gon = { emoji_skin_tone: 'medium' };
    });

    it('applies the preference to a plain emoji with tones', () => {
      expect(withPreferredTone('thumbsup')).toBe('thumbsup_tone3');
    });

    it('keeps an explicitly toned name and names without tones', () => {
      expect(withPreferredTone('thumbsup_tone1')).toBe('thumbsup_tone1');
      expect(withPreferredTone('rocket')).toBe('rocket');
      expect(withPreferredTone(MIXED)).toBe(MIXED);
    });

    it('keeps the plain name without a preference', () => {
      window.gon = {};

      expect(withPreferredTone('thumbsup')).toBe('thumbsup');
    });
  });

  describe('pickerGridNames', () => {
    const names = [
      'thumbsup',
      'thumbsup_tone1',
      'thumbsup_tone5',
      'rocket',
      'wave_tone3',
      'wave',
      MIXED,
      UNMAPPED,
    ];

    it('returns the names as they are without a preference', () => {
      expect(pickerGridNames(names)).toBe(names);
    });

    it('shows one tile per emoji in the preferred tone and hides two-tone and unmapped names', () => {
      window.gon = { emoji_skin_tone: 'medium' };

      expect(pickerGridNames(names)).toEqual(['thumbsup_tone3', 'rocket', 'wave_tone3']);
    });

    it('shows the plain emoji for the default tone', () => {
      window.gon = { emoji_skin_tone: 'default' };

      expect(pickerGridNames(names)).toEqual(['thumbsup', 'rocket', 'wave']);
    });

    it('hides every two-tone and unmapped name of the fixture', () => {
      window.gon = { emoji_skin_tone: 'light' };

      expect(pickerGridNames([...skinTones.mixed, ...skinTones.unmapped])).toEqual([]);
    });
  });

  describe('collapseToPreferredTone', () => {
    const names = ['thumbsup_tone5', 'thumbsup', 'rocket', UNMAPPED, 'thumbsup_tone1', MIXED];

    it('returns the names as they are without a preference', () => {
      expect(collapseToPreferredTone(names)).toBe(names);
    });

    it('folds every tone into the preferred one at its first position and keeps the other names', () => {
      window.gon = { emoji_skin_tone: 'medium' };

      expect(collapseToPreferredTone(names)).toEqual(['thumbsup_tone3', 'rocket', UNMAPPED, MIXED]);
    });
  });

  describe('setUserSkinTone', () => {
    it('writes the tone to gon', () => {
      window.gon = { emoji_skin_tone: 'default' };

      setUserSkinTone('medium');

      expect(userSkinTone()).toBe('medium');
      expect(window.gon.emoji_skin_tone).toBe('medium');
    });

    it('re-evaluates computed properties that read the tone through the helpers', async () => {
      window.gon = { emoji_skin_tone: 'default' };
      const wrapper = shallowMount({
        template: '<span>{{ variant }}</span>',
        computed: {
          variant() {
            return preferredVariant('thumbsup');
          },
        },
      });

      expect(wrapper.text()).toBe('thumbsup');

      setUserSkinTone('medium');
      await nextTick();

      expect(wrapper.text()).toBe('thumbsup_tone3');
    });
  });

  describe('isOtherToneOfSameEmoji', () => {
    it('is false without a preference', () => {
      expect(isOtherToneOfSameEmoji('thumbsup_tone3', 'thumbsup')).toBe(false);
    });

    describe('with a preference', () => {
      beforeEach(() => {
        window.gon = { emoji_skin_tone: 'medium' };
      });

      it.each`
        name                | other               | result
        ${'thumbsup_tone3'} | ${'thumbsup'}       | ${true}
        ${'thumbsup_tone3'} | ${'thumbsup_tone1'} | ${true}
        ${'thumbsup'}       | ${'thumbsup_tone5'} | ${true}
        ${'thumbsup_tone3'} | ${'thumbsup_tone3'} | ${false}
        ${'thumbsup_tone3'} | ${'thumbsdown'}     | ${false}
        ${'rocket'}         | ${'rocket'}         | ${false}
        ${UNMAPPED}         | ${'man_in_tuxedo'}  | ${false}
      `('is $result for $name and $other', ({ name, other, result }) => {
        expect(isOtherToneOfSameEmoji(name, other)).toBe(result);
      });
    });
  });
});
