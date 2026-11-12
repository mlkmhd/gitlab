import { GlButton, GlIcon, GlSkeletonLoader } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import FeatureLibraryExplorePageButton from '~/super_sidebar/components/feature_library/feature_library_explore_page_button.vue';

describe('FeatureLibraryExplorePageButton', () => {
  let wrapper;

  const createWrapper = (propsData = {}) => {
    wrapper = mountExtended(FeatureLibraryExplorePageButton, {
      propsData: {
        title: 'Explore Premium features',
        subtitle: 'Control merges and plan work across teams',
        ...propsData,
      },
    });
  };

  const findButton = () => wrapper.findByTestId('feature-library-explore-page-button');
  const findLoadingCard = () => wrapper.findByTestId('feature-library-explore-page-button-loading');
  const findTitle = () => wrapper.findByTestId('feature-library-explore-page-button-title');
  const findSubtitle = () => wrapper.findByTestId('feature-library-explore-page-button-subtitle');
  const findIconNames = () =>
    wrapper.findAllComponents(GlIcon).wrappers.map((w) => w.props('name'));

  describe('when loaded', () => {
    beforeEach(() => createWrapper());

    it('renders a GlButton', () => {
      expect(wrapper.findComponent(GlButton).exists()).toBe(true);
    });

    it('renders the title and subtitle', () => {
      expect(findTitle().text()).toBe('Explore Premium features');
      expect(findSubtitle().text()).toBe('Control merges and plan work across teams');
    });

    it('renders the license and chevron icons', () => {
      expect(findIconNames()).toEqual(['license', 'chevron-lg-right']);
    });

    it('emits select when clicked', async () => {
      await findButton().trigger('click');

      expect(wrapper.emitted('select')).toEqual([[]]);
    });
  });

  describe('when loading', () => {
    beforeEach(() => createWrapper({ loading: true, title: '', subtitle: '' }));

    it('renders a skeleton loader in place of the content', () => {
      expect(wrapper.findComponent(GlSkeletonLoader).exists()).toBe(true);
      expect(wrapper.findComponent(GlButton).exists()).toBe(false);
      expect(findIconNames()).toEqual([]);
      expect(findTitle().exists()).toBe(false);
      expect(findSubtitle().exists()).toBe(false);
    });

    it('does not emit select when clicked', async () => {
      await findLoadingCard().trigger('click');

      expect(wrapper.emitted('select')).toBeUndefined();
    });
  });
});
