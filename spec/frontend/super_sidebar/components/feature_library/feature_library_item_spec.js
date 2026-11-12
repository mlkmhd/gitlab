import { GlButton, GlIcon, GlLink } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { assertProps } from 'helpers/assert_props';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import FeatureLibraryItem from '~/super_sidebar/components/feature_library/feature_library_item.vue';
import { TIERS } from '~/super_sidebar/components/feature_library/constants';

const baseItem = {
  id: 'repository',
  title: 'Repository',
  description: 'Browse and manage your code',
  icon: 'code',
  category: 'code',
  tier: TIERS.FREE,
  link: '/-/repository',
};

describe('FeatureLibraryItem', () => {
  let wrapper;

  const createWrapper = ({
    item = baseItem,
    pinned = false,
    solidBackground = false,
    supportsPins = true,
    variant,
  } = {}) => {
    wrapper = mountExtended(FeatureLibraryItem, {
      propsData: { item, pinned, solidBackground, supportsPins, variant },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
      attachTo: document.body,
    });
  };

  const findContent = () => wrapper.findByTestId('feature-library-item-content');
  const findTitle = () => wrapper.findByTestId('feature-library-item-title');
  const findTitleLink = () => wrapper.findComponent(GlLink);
  const findDescription = () => wrapper.findByTestId('feature-library-item-description');
  const findFooterLabel = () => wrapper.findByTestId('feature-library-item-footer-label');
  const findIcon = () => wrapper.findComponent(GlIcon);
  const findPinButton = () => wrapper.findComponent(GlButton);
  const findLearnMore = () => wrapper.findByTestId('feature-library-item-learn-more');

  describe('variant prop', () => {
    it('rejects an unknown variant', () => {
      expect(() => assertProps(FeatureLibraryItem, { item: baseItem, variant: 'unknown' })).toThrow(
        'Invalid prop: custom validator check failed for prop "variant"',
      );
    });
  });

  describe('locked variant', () => {
    const variant = 'locked';
    const lockedItem = {
      ...baseItem,
      docs_url: '/help/user/project/repository',
      label: { type: 'new', plan: 'premium', text: 'New with Premium' },
    };

    describe('with a docs URL', () => {
      beforeEach(() => createWrapper({ item: lockedItem, variant }));

      it('renders the title as plain text rather than a link to the feature', () => {
        expect(findTitle().text()).toBe('Repository');
        expect(findTitle().attributes('href')).toBeUndefined();
      });

      it('does not render a pin button, even when pins are supported', () => {
        expect(findPinButton().exists()).toBe(false);
      });

      it('renders a Learn more link that opens the docs in a new tab', () => {
        expect(findLearnMore().text()).toBe('Learn more');
        expect(findLearnMore().attributes()).toMatchObject({
          href: '/help/user/project/repository',
          target: '_blank',
          rel: 'noopener noreferrer',
          'aria-label': 'Learn more about Repository',
        });
      });

      it('renders the label text from the catalog in the footer instead of the tier', () => {
        expect(findFooterLabel().text()).toBe('New with Premium');
      });
    });

    describe('without a docs URL or label', () => {
      beforeEach(() => createWrapper({ item: baseItem, variant }));

      it('renders no Learn more link and an empty footer label', () => {
        expect(findLearnMore().exists()).toBe(false);
        expect(findFooterLabel().text()).toBe('');
      });
    });

    it('renders on the section background without a hover state', () => {
      createWrapper({ variant, solidBackground: true });

      expect(wrapper.classes()).toContain('gl-bg-section');
      expect(wrapper.classes()).not.toContain('hover:gl-shadow-md');
    });
  });

  describe('rendering', () => {
    beforeEach(() => createWrapper());

    it('renders the icon', () => {
      expect(findIcon().props('name')).toBe('code');
    });

    it('renders the title', () => {
      expect(findTitle().text()).toBe('Repository');
    });

    it('renders the description', () => {
      expect(findDescription().text()).toBe('Browse and manage your code');
    });
  });

  describe('tier label', () => {
    it.each([
      [{ tier: TIERS.PREMIUM }, 'Premium'],
      [{ tier: TIERS.ULTIMATE }, 'Ultimate'],
      [{ tier: TIERS.ADD_ON }, 'Add-on'],
      [{ tier: TIERS.FREE }, 'Free'],
      [{ tier: undefined }, 'Free'],
    ])('renders %j as "%s"', (tierProps, expected) => {
      createWrapper({ item: { ...baseItem, ...tierProps } });
      expect(findFooterLabel().text()).toBe(expected);
    });
  });

  describe('title navigation', () => {
    it('renders the title as a link', () => {
      createWrapper();
      expect(findTitle().element.tagName).toBe('A');
      expect(findTitleLink().attributes('href')).toBe('/-/repository');
    });

    it('emits navigate with the item id when the title link is clicked', async () => {
      createWrapper();
      const link = findTitleLink();
      link.element.addEventListener('click', (e) => e.preventDefault());
      await link.trigger('click');
      expect(wrapper.emitted('navigate')).toEqual([['repository']]);
    });

    it('stretches the title link over the tile content area', () => {
      createWrapper();
      // The ::after overlay stretches against the positioned content wrapper.
      expect(findContent().classes()).toContain('gl-relative');
      expect(findTitleLink().classes()).toContain('gl-stretched-link');
    });

    it('keeps the pin action outside the stretched link click target', () => {
      createWrapper();
      expect(findContent().findComponent(GlButton).exists()).toBe(false);
    });
  });

  describe('focus()', () => {
    it('moves keyboard focus to the title link when the item has a link', () => {
      createWrapper();

      wrapper.vm.focus();

      expect(document.activeElement).toBe(findTitleLink().element);
    });
  });

  describe('pin button', () => {
    it('is not rendered when pins are not supported', () => {
      createWrapper({ supportsPins: false });
      expect(findPinButton().exists()).toBe(false);
    });

    it('is rendered when pins are supported', () => {
      createWrapper({ supportsPins: true });
      expect(findPinButton().exists()).toBe(true);
    });

    it('emits pin-toggle with nextState=true and the title when not pinned', async () => {
      createWrapper({ pinned: false });
      await findPinButton().trigger('click');
      expect(wrapper.emitted('pin-toggle')).toEqual([['repository', true, 'Repository']]);
    });

    it('emits pin-toggle with nextState=false and the title when pinned', async () => {
      createWrapper({ pinned: true });
      await findPinButton().trigger('click');
      expect(wrapper.emitted('pin-toggle')).toEqual([['repository', false, 'Repository']]);
    });

    it.each([true, false])('keeps the "Pin" aria-label when pinned is %s', (pinned) => {
      createWrapper({ pinned });
      expect(findPinButton().attributes('aria-label')).toBe('Pin Repository');
    });

    it.each([true, false])('sets aria-pressed to match pinned %s', (pinned) => {
      createWrapper({ pinned });
      expect(findPinButton().attributes('aria-pressed')).toBe(String(pinned));
    });

    it('shows "Pin" tooltip when not pinned', () => {
      createWrapper({ pinned: false });
      expect(getBinding(findPinButton().element, 'gl-tooltip').value).toBe('Pin');
    });

    it('shows "Unpin" tooltip when pinned', () => {
      createWrapper({ pinned: true });
      expect(getBinding(findPinButton().element, 'gl-tooltip').value).toBe('Unpin');
    });
  });
});
