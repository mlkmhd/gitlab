import { GlLoadingIcon, GlPagination, GlFriendlyWrap, GlLink } from '@gitlab/ui';
import Vue from 'vue';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SimpleCopyButton from '~/vue_shared/components/simple_copy_button.vue';
import CiIcon from '~/vue_shared/components/ci_icon/ci_icon.vue';
import TestSearchResults from '~/ci/pipeline_details/test_reports/test_search_results.vue';
import TestCaseDetails from '~/ci/pipeline_details/test_reports/test_case_details.vue';
import { useTestReportsStore } from '~/ci/pipeline_details/stores/test_reports';
import { SEARCH_SCOPE_ALL } from '~/ci/pipeline_details/stores/test_reports/constants';

Vue.use(PiniaVuePlugin);

describe('TestSearchResults', () => {
  let wrapper;
  let pinia;
  let store;

  // Getters can't be overridden under Vue 2, so the store derives the search
  // results (icon, formattedTime, filePath) from these suites itself.
  const mockSuites = [
    {
      name: 'jest unit',
      test_cases: [
        {
          name: 'Test 1',
          classname: 'spec.test1',
          file: './spec/test1.js',
          status: 'success',
          execution_time: 1.5,
        },
      ],
    },
    {
      name: 'rspec unit',
      test_cases: [
        {
          name: 'Test 2',
          classname: 'spec.test2',
          file: './spec/test2.js',
          status: 'failed',
          execution_time: 2.1,
        },
      ],
    },
  ];
  const mockTestCaseCount = 2;

  const createComponent = ({
    isLoadingAllSuites = false,
    suites = mockSuites,
    page = 1,
    perPage = 20,
    mountFn = shallowMountExtended,
  } = {}) => {
    pinia = createTestingPinia();
    store = useTestReportsStore();
    Object.assign(store, {
      blobPath: '/blob/path',
      testReports: { test_suites: suites },
      searchScope: SEARCH_SCOPE_ALL,
      isLoadingAllSuites,
      pageInfo: {
        page,
        perPage,
      },
    });

    wrapper = mountFn(TestSearchResults, {
      pinia,
      stubs: {
        GlTable: false,
      },
    });
  };

  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findNoResultsMessage = () => wrapper.findByTestId('no-search-results');
  const findTable = () => wrapper.findByTestId('test-search-results-table');
  const findPagination = () => wrapper.findComponent(GlPagination);

  describe('when loading all suites', () => {
    beforeEach(() => {
      createComponent({ isLoadingAllSuites: true });
    });

    it('renders loading icon', () => {
      expect(findLoadingIcon().exists()).toBe(true);
      expect(findNoResultsMessage().exists()).toBe(false);
      expect(findTable().exists()).toBe(false);
    });
  });

  describe('when search has no results', () => {
    beforeEach(() => {
      createComponent({ suites: [] });
    });

    it('renders empty message and no table', () => {
      expect(findLoadingIcon().exists()).toBe(false);
      expect(findNoResultsMessage().exists()).toBe(true);
      expect(findNoResultsMessage().text()).toBe('No test cases match your search.');
      expect(findTable().exists()).toBe(false);
      expect(findPagination().exists()).toBe(false);
    });
  });

  describe('when search has results', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders table with results', () => {
      expect(findTable().exists()).toBe(true);
      expect(findNoResultsMessage().exists()).toBe(false);
    });

    it('renders pagination component', () => {
      expect(findPagination().exists()).toBe(true);
      expect(findPagination().props('totalItems')).toBe(mockTestCaseCount);
      expect(findPagination().props('perPage')).toBe(20);
    });

    describe('when page is changed', () => {
      beforeEach(() => {
        findPagination().vm.$emit('input', 2);
      });

      it('calls setPage', () => {
        expect(store.setPage).toHaveBeenCalledWith(2);
      });
    });
  });

  describe('table contents', () => {
    beforeEach(() => {
      createComponent({ mountFn: mountExtended });
    });

    it('renders the friendly-wrapped text for suiteName, classname, and name', () => {
      const friendlyWraps = wrapper.findAllComponents(GlFriendlyWrap);
      const texts = friendlyWraps.wrappers.map((w) => w.text());

      expect(texts).toContain('jest unit');
      expect(texts).toContain('spec.test1');
      expect(texts).toContain('Test 1');
    });

    it('renders file link and copy button', () => {
      const fileLink = wrapper.findComponent(GlLink);
      const copyButton = wrapper.findComponent(SimpleCopyButton);

      expect(fileLink.attributes('href')).toBe('/blob/path/spec/test1.js');
      expect(copyButton.props('text')).toBe('./spec/test1.js');
    });

    it('renders test case details modal component', () => {
      const detailsModals = wrapper.findAllComponents(TestCaseDetails);

      expect(detailsModals).toHaveLength(mockTestCaseCount);
      expect(detailsModals.at(0).props('modalId')).toBe('test-search-result-details-0');
      expect(detailsModals.at(0).props('testCase')).toEqual(store.getSearchResults[0]);
    });

    it('renders ci-icon component for status', () => {
      const icons = wrapper.findAllComponents(CiIcon);

      expect(icons).toHaveLength(mockTestCaseCount);
      expect(icons.at(0).props('status')).toEqual(store.getSearchResults[0]);
    });
  });
});
