import MockAdapter from 'axios-mock-adapter';
import { GlModal, GlSearchBoxByType } from '@gitlab/ui';
import { nextTick } from 'vue';
import { stubComponent, RENDER_ALL_SLOTS_TEMPLATE } from 'helpers/stub_component';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import waitForPromises from 'helpers/wait_for_promises';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_OK } from '~/lib/utils/http_status';
import FeatureLibraryModal from '~/super_sidebar/components/feature_library/feature_library_modal.vue';
import FeatureLibraryExplorePageButton from '~/super_sidebar/components/feature_library/feature_library_explore_page_button.vue';
import FeatureLibraryUpgradeCta from 'ee/super_sidebar/components/feature_library/feature_library_upgrade_cta.vue';
import { EVENT_SEARCH_WITH_GEMINI_IN_FEATURE_LIBRARY_MODAL } from '~/super_sidebar/tracking_constants';

jest.mock('~/lib/utils/path_helpers/feature_library', () => ({
  onboardingFeatureLibrarySearchPath: () => '/-/onboarding/feature_library/search',
  onboardingFeatureLibraryAiSearchPath: () => '/-/onboarding/feature_library/ai_search',
  onboardingFeatureLibraryCatalogPath: () => '/-/onboarding/feature_library/catalog',
}));

const SEARCH_URL = '/-/onboarding/feature_library/search';
const AI_SEARCH_URL = '/-/onboarding/feature_library/ai_search';
const CATALOG_URL = '/-/onboarding/feature_library/catalog';

// The search_with_gemini_in_feature_library_modal event is EE-only (tiers:
// premium, ultimate), so its definition lives in ee/config/events/.
// FeatureLibraryModal behavior is covered in the CE spec:
// spec/frontend/super_sidebar/components/feature_library/feature_library_modal_spec.js
describe('FeatureLibraryModal (EE)', () => {
  let wrapper;
  let mockAxios;

  const defaultSections = [
    {
      id: 'code_menu',
      title: 'Code',
      items: [
        {
          id: 'repository',
          title: 'Repository',
          description: 'Browse and manage your code',
          library_icon: 'code',
        },
      ],
    },
  ];

  beforeEach(() => {
    mockAxios = new MockAdapter(axios);
  });

  afterEach(() => {
    mockAxios.restore();
  });

  const createWrapper = ({
    aiSearchAvailable = true,
    resourceId = 1,
    panelType = 'project',
    explorePagesAvailable = false,
  } = {}) => {
    wrapper = shallowMountExtended(FeatureLibraryModal, {
      propsData: { sections: defaultSections },
      provide: { panelType, aiSearchAvailable, resourceId, explorePagesAvailable },
      stubs: { GlModal: stubComponent(GlModal, { template: RENDER_ALL_SLOTS_TEMPLATE }) },
    });
  };

  const findSearch = () => wrapper.findComponent(GlSearchBoxByType);
  const findGeminiButton = () => wrapper.findComponentByTestId('search-with-gemini-button');

  const emitSearch = async (query) => {
    await findSearch().vm.$emit('input', query);
  };

  describe('Gemini tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();
    const CATEGORY = undefined;

    beforeEach(() => {
      mockAxios.onGet(SEARCH_URL).reply(HTTP_STATUS_OK, { ids: [] });
      mockAxios.onGet(AI_SEARCH_URL).reply(HTTP_STATUS_OK, { ids: [], ai_search_available: true });
      createWrapper();
    });

    it('tracks the Gemini search event when the button is clicked', async () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);
      await emitSearch('re');
      await waitForPromises();
      await findGeminiButton().vm.$emit('click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        EVENT_SEARCH_WITH_GEMINI_IN_FEATURE_LIBRARY_MODAL,
        {},
        CATEGORY,
      );
    });
  });

  describe('Explore page call to action', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();
    const cta = { type: 'upgrade', text: 'Upgrade to Premium', url: 'https://example.com/premium' };
    const page = (plan, pageCta) => ({
      plan,
      title: `Explore ${plan} features`,
      cta: pageCta,
      highlights: [],
      credits: [],
      categories: [],
    });

    const findUpgradeCta = () => wrapper.findComponent(FeatureLibraryUpgradeCta);
    const openExplorePage = async (title) => {
      wrapper
        .findAllComponents(FeatureLibraryExplorePageButton)
        .wrappers.find((w) => w.props('title') === title)
        .vm.$emit('select');
      await nextTick();
    };

    beforeEach(async () => {
      mockAxios.onGet(CATALOG_URL).reply(HTTP_STATUS_OK, {
        current_plan_context: { base_plan: 'free', trial: false },
        pages: [page('premium', cta), page('ultimate', null)],
      });
      createWrapper({ explorePagesAvailable: true });
      wrapper.findComponent(GlModal).vm.$emit('show');
      await waitForPromises();
    });

    describe('when a page has a call to action', () => {
      beforeEach(() => openExplorePage('Explore premium features'));

      it('renders it in the header', () => {
        expect(findUpgradeCta().props('cta')).toEqual(cta);
      });

      it.each(['upgrade', 'talk_to_sales'])('tracks a click on a "%s" call to action', (type) => {
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);
        findUpgradeCta().vm.$emit('click', type);

        expect(trackEventSpy).toHaveBeenCalledWith(
          'click_upgrade_cta_in_feature_library_modal',
          { label: 'premium', property: type },
          undefined,
        );
      });

      it('removes it when going back to the list', async () => {
        wrapper.findComponentByTestId('feature-library-back').vm.$emit('click');
        await nextTick();

        expect(findUpgradeCta().exists()).toBe(false);
      });
    });

    describe('when a page has no call to action', () => {
      beforeEach(() => openExplorePage('Explore ultimate features'));

      it('renders none', () => {
        expect(findUpgradeCta().exists()).toBe(false);
      });
    });
  });
});
