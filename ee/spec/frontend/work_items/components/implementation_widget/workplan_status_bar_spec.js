import { shallowMount } from '@vue/test-utils';
import WorkplanStatusBar from 'ee/work_items/components/implementation_widget/workplan_status_bar.vue';

// jsdom drops `var()` and gradient values, so return plain ones it keeps.
jest.mock('ee/work_items/components/implementation_widget/utils', () => ({
  getVariantColor: (variant) => (variant === 'duo' ? 'url(duo.png)' : 'red'),
}));

describe('WorkplanStatusBar', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMount(WorkplanStatusBar, {
      propsData: { variant: 'placeholder', ...props },
    });
  };

  it('stretches to fill its parent height', () => {
    createComponent();

    expect(wrapper.classes()).toEqual(expect.arrayContaining(['gl-h-full', 'gl-self-stretch']));
  });

  describe('when the variant is `duo`', () => {
    beforeEach(() => {
      createComponent({ variant: 'duo' });
    });

    it('animates the bar', () => {
      expect(wrapper.classes()).toContain('workplan-status-bar-animated');
    });

    it('sets only the background image, so the animation keeps its background size', () => {
      expect(wrapper.attributes('style')).toBe('background-image: url(duo.png);');
    });
  });

  describe('when the variant is not `duo`', () => {
    beforeEach(() => {
      createComponent({ variant: 'success' });
    });

    it('does not animate the bar', () => {
      expect(wrapper.classes()).not.toContain('workplan-status-bar-animated');
    });

    it('sets the background', () => {
      expect(wrapper.attributes('style')).toBe('background: red;');
    });
  });
});
