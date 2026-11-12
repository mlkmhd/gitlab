import { nextTick } from 'vue';
import { GlButton } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import SkinToneSelector from '~/emoji/components/skin_tone_selector.vue';

describe('SkinToneSelector', () => {
  let wrapper;

  const createComponent = (value = 'medium') => {
    wrapper = mountExtended(SkinToneSelector, {
      propsData: { value },
      attachTo: document.body,
    });
  };

  const findToggle = () => wrapper.findByTestId('skin-tone-toggle');
  const findOptionsRow = () => wrapper.findByTestId('skin-tone-options');
  const findOptions = () => wrapper.findAllByTestId('skin-tone-option');
  const findOption = (tone) => wrapper.find(`[data-tone="${tone}"]`);
  const emojiName = (element) => element.find('gl-emoji').attributes('data-name');

  const expand = async () => {
    await findToggle().trigger('click');
    await nextTick();
  };

  describe('collapsed', () => {
    it('shows one hand in the current tone with the tooltip', () => {
      createComponent('medium');

      expect(findOptionsRow().exists()).toBe(false);
      expect(emojiName(findToggle())).toBe('raised_hand_tone3');
      expect(findToggle().attributes('title')).toBe('Choose your default skin tone');
      expect(findToggle().attributes('aria-label')).toBe('Choose your default skin tone');
    });

    it('shows the plain hand for the default tone', () => {
      createComponent('default');

      expect(emojiName(findToggle())).toBe('raised_hand');
    });
  });

  describe('expanded', () => {
    beforeEach(async () => {
      createComponent('medium');
      await expand();
    });

    it('emits expand and replaces the hand with six circular radios', () => {
      expect(wrapper.emitted('expand')).toHaveLength(1);
      expect(findToggle().exists()).toBe(false);
      expect(findOptionsRow().attributes('role')).toBe('radiogroup');
      expect(findOptionsRow().attributes('title')).toBe('Choose your default skin tone');
      expect(findOptions()).toHaveLength(6);
      expect(findOptions().wrappers.map((option) => emojiName(option))).toEqual([
        'raised_hand',
        'raised_hand_tone1',
        'raised_hand_tone2',
        'raised_hand_tone3',
        'raised_hand_tone4',
        'raised_hand_tone5',
      ]);
      expect(findOptions().wrappers.map((option) => option.attributes('aria-label'))).toEqual([
        'Default',
        'Light',
        'Medium-light',
        'Medium',
        'Medium-dark',
        'Dark',
      ]);
      findOptions().wrappers.forEach((option) => {
        expect(option.classes()).toContain('!gl-rounded-full');
        expect(option.attributes('role')).toBe('radio');
      });
    });

    it('marks and focuses the current tone', () => {
      const current = findOption('medium');

      expect(current.attributes('aria-checked')).toBe('true');
      expect(current.attributes('tabindex')).toBe('0');
      expect(
        wrapper
          .findAllComponents(GlButton)
          .wrappers.find((b) => b.props('selected'))
          .attributes('data-tone'),
      ).toBe('medium');
      expect(findOption('dark').attributes('aria-checked')).toBe('false');
      expect(findOption('dark').attributes('tabindex')).toBe('-1');
      expect(document.activeElement).toBe(current.element);
    });

    it('emits the chosen tone, collapses and returns focus to the hand', async () => {
      await findOption('dark').trigger('click');
      await nextTick();

      expect(wrapper.emitted('input')).toEqual([['dark']]);
      expect(wrapper.emitted('collapse')).toHaveLength(1);
      expect(findOptionsRow().exists()).toBe(false);
      expect(document.activeElement).toBe(findToggle().element);
    });

    it('only collapses when the current tone is chosen again', async () => {
      await findOption('medium').trigger('click');

      expect(wrapper.emitted('input')).toBeUndefined();
      expect(wrapper.emitted('collapse')).toHaveLength(1);
    });

    it('collapses on Escape without closing the surrounding dropdown', async () => {
      const outerKeydown = jest.fn();
      document.body.addEventListener('keydown', outerKeydown);

      await findOption('medium').trigger('keydown', { key: 'Escape' });
      await nextTick();

      expect(outerKeydown).not.toHaveBeenCalled();
      expect(wrapper.emitted('input')).toBeUndefined();
      expect(findOptionsRow().exists()).toBe(false);
      expect(document.activeElement).toBe(findToggle().element);
    });

    it.each`
      key             | from         | to
      ${'ArrowRight'} | ${'medium'}  | ${'medium_dark'}
      ${'ArrowDown'}  | ${'medium'}  | ${'medium_dark'}
      ${'ArrowLeft'}  | ${'medium'}  | ${'medium_light'}
      ${'ArrowUp'}    | ${'medium'}  | ${'medium_light'}
      ${'ArrowRight'} | ${'dark'}    | ${'default'}
      ${'ArrowLeft'}  | ${'default'} | ${'dark'}
    `('moves focus from $from to $to on $key', async ({ key, from, to }) => {
      await findOption(from).trigger('keydown', { key });

      expect(document.activeElement).toBe(findOption(to).element);
    });
  });
});
