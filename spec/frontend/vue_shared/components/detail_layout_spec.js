import { nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import { GlLoadingIcon } from '@gitlab/ui';
import { useFakeRequestAnimationFrame } from 'helpers/fake_request_animation_frame';
import { useMockResizeObserver } from 'helpers/mock_dom_observer';
import BaseLayout from '~/vue_shared/components/base_layout.vue';
import DetailLayout from '~/vue_shared/components/detail_layout.vue';

describe('DetailLayout', () => {
  let wrapper;

  useFakeRequestAnimationFrame();

  const createComponent = (props = {}, slots = {}) => {
    wrapper = mount(DetailLayout, {
      propsData: props,
      slots,
    });
  };

  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findContainer = () => wrapper.find('[data-testid="detail-layout-container"]');
  const findSidebar = () => wrapper.find('[data-testid="detail-layout-sidebar"]');
  const findContent = () => wrapper.find('[data-testid="detail-layout-content"]');

  describe('loading', () => {
    const findSkeleton = () => wrapper.find('[data-testid="detail-layout-skeleton"]');
    const findSkeletonRegion = (region) =>
      wrapper.find(`[data-testid="detail-layout-skeleton-${region}"]`);

    it('does not render container, content, or sidebar slot when loading', () => {
      createComponent(
        { heading: 'Test Heading', loading: true },
        { default: '<div>Content</div>', sidebar: '<div>Sidebar</div>' },
      );
      expect(findSkeleton().exists()).toBe(true);
      expect(findContainer().exists()).toBe(false);
      expect(findContent().exists()).toBe(false);
      expect(findSidebar().exists()).toBe(false);
    });

    it('renders content and sidebar slot when not loading', () => {
      createComponent(
        { heading: 'Test Heading', loading: false },
        { default: '<div>Content</div>', sidebar: '<div>Sidebar</div>' },
      );
      expect(findSkeleton().exists()).toBe(false);
      expect(findLoadingIcon().exists()).toBe(false);
      expect(findContainer().exists()).toBe(true);
      expect(findContent().text()).toContain('Content');
      expect(findSidebar().text()).toContain('Sidebar');
    });

    it('only renders skeleton regions for the slots that are used', () => {
      createComponent({ loading: true }, { default: 'Content', activity: 'Activity' });
      expect(findSkeletonRegion('content').exists()).toBe(true);
      expect(findSkeletonRegion('activity').exists()).toBe(true);
      expect(findSkeletonRegion('sidebar').exists()).toBe(false);
      expect(findSkeletonRegion('widgets').exists()).toBe(false);
      expect(findSkeleton().classes()).not.toContain('gl-detail-layout-container-has-sidebar');
    });

    it('renders all skeleton regions when all slots are used', () => {
      createComponent(
        { loading: true },
        { default: 'Content', sidebar: 'Sidebar', widgets: 'Widgets', activity: 'Activity' },
      );
      ['content', 'sidebar', 'widgets', 'activity'].forEach((region) => {
        expect(findSkeletonRegion(region).exists()).toBe(true);
      });
      expect(findSkeleton().classes()).toContain('gl-detail-layout-container-has-sidebar');
    });

    it('does not render the sidebar skeleton when showSidebar is false', () => {
      createComponent({ loading: true, showSidebar: false }, { sidebar: 'Sidebar' });
      expect(findSkeletonRegion('sidebar').exists()).toBe(false);
    });

    it('renders a custom loading slot instead of the skeleton', () => {
      createComponent({ loading: true }, { loading: '<div>Custom loading</div>' });
      expect(wrapper.text()).toContain('Custom loading');
      expect(findSkeleton().exists()).toBe(false);
    });
  });

  describe('slots', () => {
    describe('sidebar', () => {
      it('renders sidebar container when slot is provided', () => {
        createComponent({}, { sidebar: '<div>Content</div>' });
        expect(findSidebar().exists()).toBe(true);
      });

      it('does not render sidebar container when slots are not provided', () => {
        createComponent();
        expect(findSidebar().exists()).toBe(false);
      });
    });

    describe('default', () => {
      it('renders body when default slot is provided', () => {
        createComponent({}, { default: '<div>Content</div>' });
        expect(findContent().exists()).toBe(true);
      });
    });
  });

  describe('sidebar space', () => {
    const SPACE_VAR = '--detail-layout-sidebar-space';
    let scrollContainer;
    let sidebarTopSpy;
    const { trigger: triggerResize } = useMockResizeObserver();

    const getSpace = () => findSidebar().element.style.getPropertyValue(SPACE_VAR);

    const setSidebarTop = (top) => sidebarTopSpy.mockReturnValue({ top });

    const spyOnSidebar = (sidebarTop) => {
      sidebarTopSpy = jest.spyOn(findSidebar().element, 'getBoundingClientRect');
      setSidebarTop(sidebarTop);
    };

    const mountInScrollContainer = ({
      containerTop = 0,
      sidebarTop = 0,
      scrollTop = 0,
      loading = false,
    } = {}) => {
      scrollContainer = document.createElement('div');
      scrollContainer.className = 'panel-content-inner';
      document.body.appendChild(scrollContainer);

      createComponent(
        { loading },
        { default: '<div>Content</div>', sidebar: '<div>Sidebar</div>' },
      );
      scrollContainer.appendChild(wrapper.element);

      jest.spyOn(scrollContainer, 'getBoundingClientRect').mockReturnValue({ top: containerTop });
      Object.defineProperty(scrollContainer, 'scrollTop', { value: scrollTop, configurable: true });
      if (!loading) spyOnSidebar(sidebarTop);
    };

    const flush = async () => {
      await nextTick();
    };

    const scroll = async () => {
      scrollContainer.dispatchEvent(new Event('scroll'));
      await flush();
    };

    afterEach(() => {
      scrollContainer?.remove();
    });

    it('sets the space to the distance from the container top to the sidebar top', async () => {
      mountInScrollContainer({ containerTop: 0, sidebarTop: 120 });
      await flush();

      expect(getSpace()).toBe('120px');
    });

    it('clamps a negative distance to zero', async () => {
      mountInScrollContainer({ containerTop: 200, sidebarTop: 100 });
      await flush();

      expect(getSpace()).toBe('0px');
    });

    it('re-measures live on scroll so the cap tracks the sidebar position', async () => {
      mountInScrollContainer({ containerTop: 0, sidebarTop: 120 });
      await flush();
      expect(getSpace()).toBe('120px');

      setSidebarTop(40);
      await scroll();

      expect(getSpace()).toBe('40px');
    });

    it('re-measures on resize', async () => {
      mountInScrollContainer({ containerTop: 0, sidebarTop: 120 });
      await flush();

      setSidebarTop(80);
      window.dispatchEvent(new Event('resize'));
      await flush();

      expect(getSpace()).toBe('80px');
    });

    it('re-measures when the layout content resizes', async () => {
      mountInScrollContainer({ containerTop: 0, sidebarTop: 120 });
      await flush();
      expect(getSpace()).toBe('120px');

      setSidebarTop(80);
      triggerResize(wrapper.element);
      await flush();

      expect(getSpace()).toBe('80px');
    });

    it('re-measures when the sticky header sticks or unsticks', async () => {
      mountInScrollContainer({ containerTop: 0, sidebarTop: 12 });
      await flush();
      expect(getSpace()).toBe('12px');

      setSidebarTop(45);
      wrapper.findComponent(BaseLayout).vm.$emit('sticky-change', true);
      await flush();

      expect(getSpace()).toBe('45px');
    });

    it('re-measures when the sidebar top transition ends', async () => {
      mountInScrollContainer({ containerTop: 0, sidebarTop: 12 });
      await flush();

      setSidebarTop(30);
      findSidebar().element.dispatchEvent(new Event('transitionend'));
      await flush();

      expect(getSpace()).toBe('30px');
    });

    describe('when the sidebar is sticky', () => {
      const STICKY_HEADER_HEIGHT = 21;
      const SPACING = 12;
      const STUCK_TOP = STICKY_HEADER_HEIGHT + SPACING;

      const mountSticky = ({ gridTop, staleSidebarTop }) => {
        mountInScrollContainer({ containerTop: 0, sidebarTop: staleSidebarTop });

        const sidebarEl = findSidebar().element;
        const realGetComputedStyle = window.getComputedStyle;
        jest.spyOn(window, 'getComputedStyle').mockImplementation((el, ...args) => {
          if (el === sidebarEl) {
            return {
              position: 'sticky',
              top: `${STUCK_TOP}px`,
              marginTop: `-${SPACING}px`,
            };
          }
          return realGetComputedStyle(el, ...args);
        });

        jest
          .spyOn(findContainer().element, 'getBoundingClientRect')
          .mockReturnValue({ top: gridTop });
      };

      it('uses the stuck position instead of a stale sidebar rect', async () => {
        mountSticky({ gridTop: -5000, staleSidebarTop: 22.5 });
        await scroll();

        expect(getSpace()).toBe(`${STUCK_TOP}px`);
      });

      it('does not subtract the negative top margin from the stuck position', async () => {
        mountSticky({ gridTop: -2000, staleSidebarTop: STICKY_HEADER_HEIGHT });
        await scroll();

        expect(getSpace()).toBe('33px');
      });

      it('uses the natural position when not stuck', async () => {
        // Grid top 132px minus the 12px negative margin puts the sidebar at 120px.
        mountSticky({ gridTop: 132, staleSidebarTop: 0 });
        await scroll();

        expect(getSpace()).toBe('120px');
      });
    });

    it('wires up the scroll sync once the sidebar renders after loading completes', async () => {
      mountInScrollContainer({ containerTop: 0, loading: true });
      await flush();
      // Sidebar is not rendered while loading, so nothing is measured yet.
      expect(findSidebar().exists()).toBe(false);

      // Loading completes: the sidebar renders and the sync must wire up against it.
      wrapper.setProps({ loading: false });
      await flush();
      spyOnSidebar(120);

      // A scroll now drives a measurement, proving the listener was attached.
      await scroll();

      expect(getSpace()).toBe('120px');
    });
  });

  describe('hidePageHeading', () => {
    it('passes hidePageHeading to BaseLayout', () => {
      createComponent({ heading: 'Test Heading', hidePageHeading: true });
      expect(wrapper.findComponent(BaseLayout).props('hidePageHeading')).toBe(true);
      expect(wrapper.find('[data-testid="page-heading"]').exists()).toBe(false);
    });
  });

  describe('showSidebar', () => {
    it('applies the has-sidebar class by default when sidebar slot is provided', () => {
      createComponent({}, { sidebar: '<div>Sidebar</div>' });
      expect(findContainer().classes()).toContain('gl-detail-layout-container-has-sidebar');
    });

    it('does not apply the has-sidebar class when showSidebar is false, but keeps the sidebar in the DOM', () => {
      createComponent({ showSidebar: false }, { sidebar: '<div>Sidebar</div>' });
      expect(findContainer().classes()).not.toContain('gl-detail-layout-container-has-sidebar');
      expect(findSidebar().exists()).toBe(true);
    });

    it('makes the sidebar wrapper display:contents when showSidebar is false so it reserves no grid space', () => {
      createComponent({ showSidebar: false }, { sidebar: '<div>Sidebar</div>' });
      expect(findSidebar().classes()).toContain('gl-contents');
    });

    it('does not make the sidebar wrapper display:contents by default', () => {
      createComponent({}, { sidebar: '<div>Sidebar</div>' });
      expect(findSidebar().classes()).not.toContain('gl-contents');
    });
  });

  describe('animateStickyHeader', () => {
    it.each`
      animateStickyHeader | hasClass
      ${true}             | ${false}
      ${false}            | ${true}
    `(
      'sets the sidebar no-animation class to $hasClass when animateStickyHeader is $animateStickyHeader',
      ({ animateStickyHeader, hasClass }) => {
        createComponent({ animateStickyHeader }, { sidebar: '<div>Sidebar</div>' });

        expect(findSidebar().classes('gl-detail-layout-sidebar-no-animation')).toBe(hasClass);
      },
    );
  });
});
