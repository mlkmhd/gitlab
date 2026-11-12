import { GlButton } from '@gitlab/ui';
import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import { copyToClipboard } from '~/lib/utils/copy_to_clipboard';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { hideGlTooltip } from '~/vue_shared/utils/tooltips';

import SimpleCopyButton from '~/vue_shared/components/simple_copy_button.vue';

jest.mock('~/lib/utils/copy_to_clipboard');
jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('~/vue_shared/utils/tooltips');

describe('clipboard button', () => {
  let wrapper;

  const createWrapper = ({ props, ...options } = {}) => {
    wrapper = mount(SimpleCopyButton, {
      propsData: {
        text: 'copy me',
        ...props,
      },
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
      ...options,
    });
  };

  const findButton = () => wrapper.findComponent(GlButton);
  const getTooltip = () => getBinding(findButton().element, 'gl-tooltip');

  const clickButton = async () => {
    findButton().vm.$emit('click');
    await waitForPromises();
  };

  const endFeedback = async () => {
    jest.advanceTimersByTime(SimpleCopyButton.FEEDBACK_DURATION_MS);
    await nextTick();
  };

  beforeEach(() => {
    copyToClipboard.mockResolvedValue();
  });

  describe('default options', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('renders a button to copy', () => {
      expect(findButton().props('category')).toBe('secondary');
      expect(findButton().props('size')).toBe('medium');
      expect(findButton().props('variant')).toBe('default');
      expect(findButton().props('icon')).toBe('copy-to-clipboard');

      expect(findButton().attributes('aria-live')).toBeUndefined();
      expect(findButton().attributes('aria-label')).toBe('Copy');
    });

    it('configures tooltip', () => {
      expect(getTooltip()).toMatchObject({
        value: { placement: 'top', title: 'Copy' },
      });
    });

    describe('when clicked', () => {
      beforeEach(async () => {
        await clickButton();
      });

      it('copies', () => {
        expect(copyToClipboard).toHaveBeenCalledWith('copy me', wrapper.element);
      });

      it('shows the check icon for 2 seconds', async () => {
        expect(findButton().props('icon')).toBe('check');

        await endFeedback();

        expect(findButton().props('icon')).toBe('copy-to-clipboard');
      });

      it('announces the result', () => {
        expect(wrapper.element.ariaNotify).toHaveBeenCalledTimes(1);
        expect(wrapper.element.ariaNotify).toHaveBeenCalledWith('Copied to clipboard.');
      });

      it('does not change the tooltip and the accessible name', () => {
        expect(getTooltip()).toMatchObject({ value: { title: 'Copy' } });
        expect(findButton().attributes('aria-label')).toBe('Copy');
      });

      it('emits "copied" event', () => {
        expect(wrapper.emitted('copied')).toEqual([[]]);
      });
    });

    it('restarts the 2 seconds when copying again', async () => {
      await clickButton();
      jest.advanceTimersByTime(1500);
      await clickButton();
      jest.advanceTimersByTime(1500);
      await nextTick();

      expect(findButton().props('icon')).toBe('check');

      jest.advanceTimersByTime(500);
      await nextTick();

      expect(findButton().props('icon')).toBe('copy-to-clipboard');
    });

    describe('when the pointer leaves', () => {
      beforeEach(() => {
        findButton().vm.$emit('mouseleave');
      });

      it('hides tooltip', () => {
        expect(hideGlTooltip).toHaveBeenCalledWith(expect.anything(), wrapper.element.id);
      });
    });
  });

  describe('customization', () => {
    beforeEach(() => {
      createWrapper({
        props: {
          category: 'tertiary',
          size: 'small',
          variant: 'confirm',
          icon: 'pencil',
          ariaLabel: 'My aria label',
          title: 'My title',
        },
      });
    });

    it('renders a button to copy with other options', () => {
      expect(findButton().props('category')).toBe('tertiary');
      expect(findButton().props('size')).toBe('small');
      expect(findButton().props('variant')).toBe('confirm');
      expect(findButton().props('icon')).toBe('pencil');

      expect(findButton().attributes('aria-label')).toBe('My aria label');

      expect(getTooltip()).toMatchObject({
        value: { title: 'My title' },
      });
    });

    it('goes back to the custom icon after copying', async () => {
      await clickButton();
      expect(findButton().props('icon')).toBe('check');

      await endFeedback();

      expect(findButton().props('icon')).toBe('pencil');
    });
  });

  describe('on error', () => {
    beforeEach(() => {
      createWrapper();

      copyToClipboard.mockRejectedValue(new Error('error copying'));
    });

    describe('when clicked', () => {
      beforeEach(async () => {
        await clickButton();
      });

      it('tries to copy', () => {
        expect(copyToClipboard).toHaveBeenCalledWith('copy me', wrapper.element);
      });

      it('shows the error icon for 2 seconds and announces the error', async () => {
        expect(findButton().props('icon')).toBe('error');
        expect(wrapper.element.ariaNotify).toHaveBeenCalledWith(
          'Copy failed. Please manually copy the value.',
        );

        await endFeedback();

        expect(findButton().props('icon')).toBe('copy-to-clipboard');
      });

      it('emits "error" event and reports to sentry', () => {
        expect(wrapper.emitted('error')).toEqual([[new Error('error copying')]]);

        expect(Sentry.captureException).toHaveBeenCalledWith(new Error('error copying'));
      });
    });
  });
});
