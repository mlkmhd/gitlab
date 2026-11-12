import { nextTick } from 'vue';
import { GlLoadingIcon, GlIntersectionObserver } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { useMockResizeObserver } from 'helpers/mock_dom_observer';
import waitForPromises from 'helpers/wait_for_promises';
import BaseLayout from '~/vue_shared/components/base_layout.vue';
import PageHeading from '~/vue_shared/components/page_heading.vue';

describe('BaseLayout', () => {
  let wrapper;

  const createComponent = (props = {}, slots = {}) => {
    wrapper = mountExtended(BaseLayout, {
      propsData: props,
      slots,
    });
  };

  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findPageHeading = () => wrapper.findComponent(PageHeading);
  const findHeading = () => wrapper.findByTestId('page-heading');
  const findDescription = () => wrapper.findByTestId('page-heading-description');
  const findActions = () => wrapper.findByTestId('page-heading-actions');
  const findAlerts = () => wrapper.findByTestId('base-layout-alerts');
  const findContent = () => wrapper.findByTestId('base-layout-content');
  const findStickyHeader = () => wrapper.findByTestId('base-layout-sticky-header');
  const findIntersectionObserver = () => wrapper.findComponent(GlIntersectionObserver);

  describe('PageHeading', () => {
    describe('heading', () => {
      it('renders when heading prop is provided', () => {
        createComponent({ heading: 'Test Heading' });
        expect(findPageHeading().exists()).toBe(true);
        expect(findPageHeading().props('heading')).toBe('Test Heading');
      });

      it('renders when heading slot is provided', () => {
        createComponent({}, { heading: 'Custom Heading' });
        expect(findHeading().exists()).toBe(true);
      });

      it('renders actions inline with the heading', () => {
        createComponent({ heading: 'Test Heading' });
        expect(findPageHeading().props('inlineActions')).toBe(true);
      });
    });

    describe('description', () => {
      it('renders description when prop provided', () => {
        createComponent({ heading: 'Test Heading', description: 'Test description' });
        expect(findDescription().exists()).toBe(true);
      });

      it('renders description when slot provided', () => {
        createComponent({ heading: 'Test Heading' }, { description: 'Test description' });
        expect(findDescription().exists()).toBe(true);
      });

      it('does not render when no description prop or slot is provided', () => {
        createComponent({ heading: 'Test Heading' });
        expect(findDescription().exists()).toBe(false);
      });
    });

    describe('actions', () => {
      it('renders actions when slot provided', () => {
        createComponent({ heading: 'Test Heading' }, { actions: 'Test action' });
        expect(findActions().exists()).toBe(true);
      });

      it('does not render when no actions slot is provided', () => {
        createComponent({ heading: 'Test Heading' });
        expect(findActions().exists()).toBe(false);
      });
    });
  });

  describe('headingTag', () => {
    it('defaults to null', () => {
      createComponent();
      expect(findPageHeading().props('headingTag')).toBeNull();
    });

    it('passes headingTag prop to PageHeading', () => {
      createComponent({ headingTag: 'h2' });
      expect(findPageHeading().props('headingTag')).toBe('h2');
    });
  });

  describe('pageHeadingSrOnly', () => {
    it('does not apply gl-sr-only class by default', () => {
      createComponent({ heading: 'Test Heading' });
      expect(findPageHeading().classes()).not.toContain('gl-sr-only');
    });

    it('applies gl-sr-only class when pageHeadingSrOnly is true', () => {
      createComponent({ heading: 'Test Heading', pageHeadingSrOnly: true });
      expect(findPageHeading().classes()).toContain('gl-sr-only');
    });
  });

  describe('hidePageHeading', () => {
    it('renders PageHeading by default', () => {
      createComponent({ heading: 'Test Heading' });
      expect(findPageHeading().exists()).toBe(true);
    });

    it('does not render PageHeading when hidePageHeading is true', () => {
      createComponent({ heading: 'Test Heading', hidePageHeading: true });
      expect(findPageHeading().exists()).toBe(false);
      expect(findHeading().exists()).toBe(false);
    });
  });

  describe('loading', () => {
    const findSkeleton = () => wrapper.findByTestId('base-layout-skeleton');
    const findSkeletonContent = () => wrapper.findByTestId('base-layout-skeleton-content');
    const findHeadingSkeleton = () => wrapper.findByTestId('base-layout-heading-skeleton');

    it('does not render a loading state by default', () => {
      createComponent({ heading: 'Test Heading' });
      expect(findLoadingIcon().exists()).toBe(false);
      expect(findSkeleton().exists()).toBe(false);
      expect(findHeadingSkeleton().exists()).toBe(false);
    });

    it('renders the content skeleton when loading prop is true', () => {
      createComponent({ heading: 'Test Heading', loading: true });
      expect(findSkeleton().attributes('role')).toBe('status');
      expect(findSkeleton().text()).toBe('Loading');
      expect(findSkeletonContent().exists()).toBe(true);
      expect(findLoadingIcon().exists()).toBe(false);
    });

    it('does not render content slot when loading', () => {
      createComponent(
        { heading: 'Test Heading', loading: true },
        { default: '<div>Content</div>' },
      );
      expect(findSkeleton().exists()).toBe(true);
      expect(findContent().text()).not.toContain('Content');
    });

    it('renders content slot when not loading', () => {
      createComponent(
        { heading: 'Test Heading', loading: false },
        { default: '<div>Content</div>' },
      );
      expect(findSkeleton().exists()).toBe(false);
      expect(findContent().text()).toContain('Content');
    });

    it('renders the loading-skeleton slot instead of the default skeleton', () => {
      createComponent({ loading: true }, { 'loading-skeleton': '<div>Custom skeleton</div>' });
      expect(findSkeleton().text()).toContain('Custom skeleton');
      expect(findSkeletonContent().exists()).toBe(false);
    });

    describe('heading skeleton', () => {
      it('keeps the heading-wrapper slot', () => {
        createComponent({ loading: true }, { 'heading-wrapper': '<div>Wrapper</div>' });
        expect(findHeadingSkeleton().exists()).toBe(false);
        expect(wrapper.text()).toContain('Wrapper');
      });

      it('renders the heading-wrapper slot when not loading', () => {
        createComponent({}, { 'heading-wrapper': '<div>Wrapper</div>' });
        expect(findHeadingSkeleton().exists()).toBe(false);
        expect(wrapper.text()).toContain('Wrapper');
      });

      it('renders when the heading is empty', () => {
        createComponent({ loading: true });
        expect(findHeadingSkeleton().exists()).toBe(true);
        expect(findHeading().exists()).toBe(false);
      });

      it('keeps the heading slot', () => {
        createComponent({ loading: true }, { heading: 'Slot heading' });
        expect(findHeadingSkeleton().exists()).toBe(false);
        expect(wrapper.text()).toContain('Slot heading');
      });

      it('keeps the heading prop', () => {
        createComponent({ loading: true, heading: 'Test Heading' });
        expect(findHeadingSkeleton().exists()).toBe(false);
        expect(findHeading().text()).toBe('Test Heading');
      });

      it('renders the heading prop when not loading', () => {
        createComponent({ heading: 'Test Heading' });
        expect(findHeadingSkeleton().exists()).toBe(false);
        expect(findHeading().text()).toBe('Test Heading');
      });
    });

    describe('description skeleton', () => {
      const findDescriptionSkeleton = () =>
        wrapper.findByTestId('base-layout-description-skeleton');

      it('renders when the description is empty', () => {
        createComponent({ loading: true });
        expect(findDescriptionSkeleton().exists()).toBe(true);
      });

      it('does not render when not loading', () => {
        createComponent();
        expect(findDescriptionSkeleton().exists()).toBe(false);
      });

      it('keeps the description slot', () => {
        createComponent({ loading: true }, { description: 'Slot description' });
        expect(findDescriptionSkeleton().exists()).toBe(false);
        expect(wrapper.text()).toContain('Slot description');
      });

      it('keeps the description prop', () => {
        createComponent({ loading: true, description: 'Description' });
        expect(findDescriptionSkeleton().exists()).toBe(false);
        expect(wrapper.text()).toContain('Description');
      });

      it('renders the description slot when not loading', () => {
        createComponent({}, { description: 'Slot description' });
        expect(findDescriptionSkeleton().exists()).toBe(false);
        expect(findDescription().text()).toBe('Slot description');
      });

      it('does not render when a custom loading slot is used', () => {
        createComponent({ loading: true }, { loading: 'Custom loading' });
        expect(findDescriptionSkeleton().exists()).toBe(false);
      });
    });

    describe('when a custom loading slot is provided', () => {
      it('renders only the loading slot', () => {
        createComponent({ loading: true }, { loading: '<div>Custom loading</div>' });
        expect(findContent().text()).toBe('Custom loading');
        expect(findSkeleton().exists()).toBe(false);
        expect(findHeadingSkeleton().exists()).toBe(false);
        expect(findLoadingIcon().exists()).toBe(false);
      });
    });
  });

  describe('slots', () => {
    describe('alerts', () => {
      it('renders alerts container when slot is provided', () => {
        createComponent({}, { alerts: '<div>Alerts slot content</div>' });
        expect(findAlerts().text()).toContain('Alerts slot content');
      });

      it('does not render when no alerts slot is provided', () => {
        createComponent({ heading: 'Test Heading' });
        expect(findAlerts().exists()).toBe(false);
      });
    });

    describe('default', () => {
      it('renders body when default slot is provided', () => {
        createComponent({}, { default: '<div>Content</div>' });
        expect(findContent().exists()).toBe(true);
      });
    });
  });

  describe('stickyHeader', () => {
    it('does not render the sticky header by default', () => {
      createComponent({ heading: 'Test Heading' });
      expect(findStickyHeader().exists()).toBe(false);
    });

    describe('sticky header fallback', () => {
      it('renders the sticky-header slot when provided', async () => {
        createComponent(
          { heading: 'Test Heading' },
          { 'sticky-header': '<span>Custom sticky header</span>' },
        );
        await nextTick();
        expect(findStickyHeader().text()).toBe('Custom sticky header');
      });
    });

    describe('animateStickyHeader', () => {
      it('animates the sticky header by default', () => {
        createComponent({ heading: 'Test Heading' }, { 'sticky-header': '<span>Sticky</span>' });
        expect(findStickyHeader().classes()).not.toContain(
          'gl-base-layout-sticky-header-no-animation',
        );
      });

      it('disables the animation when animateStickyHeader is false', () => {
        createComponent(
          { heading: 'Test Heading', animateStickyHeader: false },
          { 'sticky-header': '<span>Sticky</span>' },
        );
        expect(findStickyHeader().classes()).toContain('gl-base-layout-sticky-header-no-animation');
      });
    });

    describe('intersection observer options', () => {
      const STICKY_HEIGHT = 48;
      const PADDING_BOTTOM = 12;

      const { trigger: triggerResize } = useMockResizeObserver();

      // The header should stick once the heading scrolls behind the sticky header's
      // content height (its box minus the bottom padding spacer).
      const expectedRootMargin = `-${STICKY_HEIGHT - PADDING_BOTTOM}px 0px 0px 0px`;

      beforeEach(() => {
        // offsetHeight/getComputedStyle are read in mounted(), so stub before mount.
        jest.spyOn(HTMLElement.prototype, 'offsetHeight', 'get').mockReturnValue(STICKY_HEIGHT);
        jest
          .spyOn(window, 'getComputedStyle')
          .mockReturnValue({ paddingBottom: `${PADDING_BOTTOM}px` });
      });

      it('observes against the panel scroll container with a sticky-header rootMargin', async () => {
        const scrollContainer = document.createElement('div');
        scrollContainer.className = 'panel-content-inner';
        const mountPoint = document.createElement('div');
        scrollContainer.appendChild(mountPoint);
        document.body.appendChild(scrollContainer);

        wrapper = mountExtended(BaseLayout, {
          propsData: { heading: 'Test Heading' },
          slots: { 'sticky-header': '<span>Sticky</span>' },
          attachTo: mountPoint,
        });
        await nextTick();

        expect(findIntersectionObserver().props('options')).toEqual({
          root: scrollContainer,
          rootMargin: expectedRootMargin,
        });

        scrollContainer.remove();
      });

      it('falls back to the viewport root with a sticky-header rootMargin outside a panel', async () => {
        createComponent({ heading: 'Test Heading' }, { 'sticky-header': '<span>Sticky</span>' });
        await nextTick();

        expect(findIntersectionObserver().props('options')).toEqual({
          rootMargin: expectedRootMargin,
        });
      });

      it('recomputes the rootMargin when the sticky header resizes', async () => {
        jest.useFakeTimers();
        createComponent({ heading: 'Test Heading' }, { 'sticky-header': '<span>Sticky</span>' });
        await nextTick();

        const newHeight = 80;
        jest.spyOn(HTMLElement.prototype, 'offsetHeight', 'get').mockReturnValue(newHeight);

        triggerResize(findStickyHeader().element, { entry: { contentRect: {} } });
        jest.runOnlyPendingTimers();
        await waitForPromises();
        await nextTick();

        expect(findIntersectionObserver().props('options')).toEqual({
          rootMargin: `-${newHeight - PADDING_BOTTOM}px 0px 0px 0px`,
        });
        jest.useRealTimers();
      });
    });

    describe('header height CSS variable', () => {
      const HEIGHT = 64;
      const LIVE_VAR = '--layout-sticky-header-height';
      const getVar = (name) => document.documentElement.style.getPropertyValue(name).trim();

      const mountWithStickyHeader = async () => {
        createComponent({ heading: 'Test Heading' }, { 'sticky-header': '<span>Sticky</span>' });
        // The observer (and its sticky-header slot) render once the root is resolved.
        await nextTick();
        jest.spyOn(findStickyHeader().element, 'offsetHeight', 'get').mockReturnValue(HEIGHT);
      };

      afterEach(() => {
        document.documentElement.style.removeProperty(LIVE_VAR);
      });

      it('sets the live header height when the header sticks', async () => {
        await mountWithStickyHeader();

        findIntersectionObserver().vm.$emit('disappear');
        await waitForPromises();

        expect(getVar(LIVE_VAR)).toBe(`${HEIGHT}px`);
      });

      it('removes the live var when the header hides', async () => {
        await mountWithStickyHeader();

        findIntersectionObserver().vm.$emit('disappear');
        await waitForPromises();
        findIntersectionObserver().vm.$emit('appear');
        await waitForPromises();

        expect(getVar(LIVE_VAR)).toBe('');
      });

      it('emits sticky-change after the live var is set and after it is removed', async () => {
        await mountWithStickyHeader();

        findIntersectionObserver().vm.$emit('disappear');
        await waitForPromises();

        expect(getVar(LIVE_VAR)).toBe(`${HEIGHT}px`);
        expect(wrapper.emitted('sticky-change')).toEqual([[true]]);

        findIntersectionObserver().vm.$emit('appear');
        await waitForPromises();

        expect(wrapper.emitted('sticky-change')).toEqual([[true], [false]]);
      });
    });
  });
});
