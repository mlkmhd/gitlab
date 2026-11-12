import { GlButton } from '@gitlab/ui';
import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent, RENDER_ALL_SLOTS_TEMPLATE } from 'helpers/stub_component';
import FeatureLibraryExplorePage from '~/super_sidebar/components/feature_library/feature_library_explore_page.vue';
import FeatureLibraryItem from '~/super_sidebar/components/feature_library/feature_library_item.vue';
import ScrollScrim from '~/vue_shared/components/scroll_scrim/scroll_scrim.vue';

describe('FeatureLibraryExplorePage', () => {
  let wrapper;

  const item = (id) => ({ id, title: id, description: `${id} description`, icon: 'rocket' });

  const buildPage = (overrides = {}) => ({
    plan: 'premium',
    highlights_title: 'Premium highlights',
    credits_title: 'Powered by GitLab Credits',
    highlights: [item('merge_controls')],
    credits: [item('duo_agent_platform')],
    categories: [
      { id: 'plan_menu', title: 'Plan', items: [item('roadmap'), item('epics')] },
      { id: 'secure_menu', title: 'Secure', items: [item('audit_events')] },
    ],
    ...overrides,
  });

  const createWrapper = (page = buildPage()) => {
    wrapper = shallowMountExtended(FeatureLibraryExplorePage, {
      propsData: { page },
      stubs: {
        ScrollScrim: stubComponent(ScrollScrim, { template: RENDER_ALL_SLOTS_TEMPLATE }),
      },
      attachTo: document.body,
    });
  };

  const findSections = () => wrapper.findAllByTestId('feature-library-explore-section');
  const findHeadings = () => findSections().wrappers.map((w) => w.find('h3'));
  const findSectionTitles = () => findHeadings().map((w) => w.text());
  const findSectionItemIds = () =>
    findSections().wrappers.map((section) =>
      section.findAllComponents(FeatureLibraryItem).wrappers.map((w) => w.props('item').id),
    );
  const findChipGroup = () => wrapper.findByTestId('feature-library-explore-chips');
  const findChips = () => findChipGroup().findAllComponents(GlButton);
  const findChip = (title) => findChips().wrappers.find((w) => w.text() === title);
  const findSelectedChipTitles = () =>
    findChips()
      .wrappers.filter((w) => w.attributes('aria-current') === 'location')
      .map((w) => w.text());
  const findScrollArea = () => wrapper.findByTestId('feature-library-explore-scroll-area');

  describe('with every section', () => {
    beforeEach(() => createWrapper());

    it('renders the highlights, then the credits, then each category, with their titles', () => {
      expect(findSectionTitles()).toEqual([
        'Premium highlights',
        'Powered by GitLab Credits',
        'Plan',
        'Secure',
      ]);
    });

    it('renders each section’s items in order', () => {
      expect(findSectionItemIds()).toEqual([
        ['merge_controls'],
        ['duo_agent_platform'],
        ['roadmap', 'epics'],
        ['audit_events'],
      ]);
    });

    it('renders every item as locked', () => {
      const items = wrapper.findAllComponents(FeatureLibraryItem).wrappers;

      expect(items.length).toBeGreaterThan(0);
      expect(items.every((w) => w.props('variant') === 'locked')).toBe(true);
    });

    it('renders the sections in a scroll area', () => {
      expect(findScrollArea().findAllByTestId('feature-library-explore-section')).toHaveLength(
        findSections().length,
      );
    });

    it('keeps the headings focusable but out of the tab order', () => {
      expect(findHeadings().every((w) => w.attributes('tabindex') === '-1')).toBe(true);
    });
  });

  describe('with empty sections', () => {
    beforeEach(() =>
      createWrapper(
        buildPage({
          highlights: [],
          credits: [],
          categories: [{ id: 'plan_menu', title: 'Plan', items: [item('roadmap')] }],
        }),
      ),
    );

    it('renders only the sections that have items', () => {
      expect(findSectionTitles()).toEqual(['Plan']);
    });
  });

  describe('section chips', () => {
    // jsdom doesn't lay out, so the scroll area and headings get a fake geometry: a 300px tall
    // area at 100px from the top with ScrollScrim's 1px top border, over 1000px of content.
    const SCROLL_AREA_TOP = 100;
    const SCROLL_AREA_BORDER = 1;
    const HEADING_OFFSETS = [0, 200, 400, 800];

    let scrollArea;

    const scrollAreaTo = async (top) => {
      scrollArea.scrollTop = top;
      scrollArea.dispatchEvent(new Event('scroll'));
      await nextTick();
    };

    const clickChip = async (title) => {
      findChip(title).vm.$emit('click');
      await nextTick();
    };

    beforeEach(() => {
      createWrapper();

      scrollArea = findScrollArea().element;
      let scrollTop = 0;
      Object.defineProperties(scrollArea, {
        scrollTop: {
          get: () => scrollTop,
          set: (value) => {
            scrollTop = value;
          },
        },
        clientHeight: { value: 300 },
        clientTop: { value: SCROLL_AREA_BORDER },
        scrollHeight: { value: 1000 },
      });
      scrollArea.scrollTo = jest.fn();
      scrollArea.getBoundingClientRect = () => ({ top: SCROLL_AREA_TOP });

      findHeadings().forEach((heading, index) => {
        // eslint-disable-next-line no-param-reassign
        heading.element.getBoundingClientRect = () => ({
          top: SCROLL_AREA_TOP + SCROLL_AREA_BORDER + HEADING_OFFSETS[index] - scrollArea.scrollTop,
        });
      });
    });

    it('renders "All", then a chip per category in page order', () => {
      expect(findChips().wrappers.map((w) => w.text())).toEqual(['All', 'Plan', 'Secure']);
    });

    it('labels the chip group', () => {
      expect(findChipGroup().attributes()).toMatchObject({
        role: 'group',
        'aria-label': 'Jump to section',
      });
    });

    it('renders the chips as small secondary buttons', () => {
      expect(
        findChips().wrappers.every(
          (chip) => chip.props('category') === 'secondary' && chip.props('size') === 'small',
        ),
      ).toBe(true);
    });

    it('labels "All" with where it goes, keeping its visible text', () => {
      expect(findChip('All').attributes('aria-label')).toBe('All sections');
      expect(findChip('Plan').attributes('aria-label')).toBeUndefined();
    });

    it('starts with "All" selected', () => {
      expect(findSelectedChipTitles()).toEqual(['All']);
      expect(findChip('All').props('selected')).toBe(true);
      expect(findChip('Plan').props('selected')).toBe(false);
    });

    it('marks only the selected chip as the current location, not as a toggle', () => {
      expect(findChip('Plan').attributes('aria-current')).toBeUndefined();
      expect(findChips().wrappers.some((w) => w.attributes('aria-pressed'))).toBe(false);
    });

    describe('when a category chip is clicked', () => {
      beforeEach(() => clickChip('Plan'));

      it('selects the chip', () => {
        expect(findSelectedChipTitles()).toEqual(['Plan']);
      });

      it('smoothly scrolls the section heading to the top, leaving room for its focus ring', () => {
        expect(scrollArea.scrollTo).toHaveBeenCalledWith({ top: 396, behavior: 'smooth' });
      });

      it('moves focus to the section heading', () => {
        expect(document.activeElement).toBe(findHeadings()[2].element);
      });
    });

    describe('when "All" is clicked', () => {
      beforeEach(async () => {
        await scrollAreaTo(450);
        await clickChip('All');
      });

      it('scrolls back to the top', () => {
        expect(scrollArea.scrollTo).toHaveBeenCalledWith({ top: 0, behavior: 'smooth' });
      });

      it('moves focus to the first heading', () => {
        expect(document.activeElement).toBe(findHeadings()[0].element);
      });

      it('selects "All"', () => {
        expect(findSelectedChipTitles()).toEqual(['All']);
      });
    });

    describe('when the user prefers reduced motion', () => {
      beforeEach(async () => {
        jest.spyOn(window, 'matchMedia').mockReturnValue({ matches: true });
        await clickChip('Plan');
      });

      it('scrolls instantly', () => {
        expect(scrollArea.scrollTo).toHaveBeenCalledWith({ top: 396, behavior: 'auto' });
      });
    });

    describe('while scrolling', () => {
      it.each`
        scrollTop | description                                          | selected
        ${0}      | ${'at the top'}                                      | ${'All'}
        ${250}    | ${'before any category heading reaches the top'}     | ${'All'}
        ${390}    | ${'just before a category heading reaches the top'}  | ${'All'}
        ${396}    | ${'when a chip has scrolled its heading to the top'} | ${'Plan'}
        ${450}    | ${'past a category heading'}                         | ${'Plan'}
        ${700}    | ${'at the bottom, before the last heading reaches'}  | ${'Secure'}
      `('selects $selected $description', async ({ scrollTop, selected }) => {
        await scrollAreaTo(scrollTop);

        expect(findSelectedChipTitles()).toEqual([selected]);
      });
    });

    describe('when a clicked chip is locked', () => {
      beforeEach(async () => {
        await clickChip('Secure');
        await scrollAreaTo(450);
      });

      it('keeps the chip selected through its scroll', () => {
        expect(findSelectedChipTitles()).toEqual(['Secure']);
      });

      it.each(['scrollend', 'wheel', 'touchstart', 'keydown', 'pointerdown'])(
        'follows the scroll again after a %s in the scroll area',
        async (eventName) => {
          scrollArea.dispatchEvent(new Event(eventName));
          await scrollAreaTo(450);

          expect(findSelectedChipTitles()).toEqual(['Plan']);
        },
      );
    });

    describe('when "All" is clicked at the top', () => {
      beforeEach(() => clickChip('All'));

      it('follows the scroll again after the user scrolls', async () => {
        scrollArea.dispatchEvent(new Event('wheel'));
        await scrollAreaTo(450);

        expect(findSelectedChipTitles()).toEqual(['Plan']);
      });
    });
  });

  describe('without categories', () => {
    beforeEach(() => createWrapper(buildPage({ categories: [] })));

    it('renders no chips', () => {
      expect(findChipGroup().exists()).toBe(false);
    });
  });

  describe('when destroyed', () => {
    it('removes every listener it added to the scroll area', () => {
      const addEventListener = jest.spyOn(EventTarget.prototype, 'addEventListener');
      const removeEventListener = jest.spyOn(EventTarget.prototype, 'removeEventListener');
      createWrapper();
      const scrollArea = findScrollArea().element;
      const listenersOn = (spy) =>
        spy.mock.calls
          .filter((_, index) => spy.mock.contexts[index] === scrollArea)
          .map(([eventName, handler]) => [eventName, handler]);

      const added = listenersOn(addEventListener);
      wrapper.destroy();
      const removed = listenersOn(removeEventListener);

      expect(added.map(([eventName]) => eventName)).toEqual(
        expect.arrayContaining([
          'scroll',
          'scrollend',
          'wheel',
          'touchstart',
          'keydown',
          'pointerdown',
        ]),
      );
      expect(removed).toHaveLength(added.length);
      expect(removed).toEqual(expect.arrayContaining(added));
    });
  });
});
