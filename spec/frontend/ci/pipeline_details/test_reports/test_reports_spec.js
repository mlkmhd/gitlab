import { GlLoadingIcon } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import Vue from 'vue';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import testReports from 'test_fixtures/pipelines/test_report.json';
import { extendedWrapper } from 'helpers/vue_test_utils_helper';
import {
  getParameterValues,
  updateHistory,
  removeParams,
  setUrlParams,
} from '~/lib/utils/url_utility';
import EmptyState from '~/ci/pipeline_details/test_reports/empty_state.vue';
import TestReports from '~/ci/pipeline_details/test_reports/test_reports.vue';
import TestSummaryTable from '~/ci/pipeline_details/test_reports/test_summary_table.vue';
import { useTestReportsStore } from '~/ci/pipeline_details/stores/test_reports';
import {
  SEARCH_SCOPE_SUITE,
  SEARCH_SCOPE_ALL,
} from '~/ci/pipeline_details/stores/test_reports/constants';

Vue.use(PiniaVuePlugin);

jest.mock('~/lib/utils/url_utility', () => ({
  ...jest.requireActual('~/lib/utils/url_utility'),
  getParameterValues: jest.fn().mockReturnValue([]),
  updateHistory: jest.fn().mockName('updateHistory'),
  removeParams: jest.fn().mockName('removeParams'),
  setUrlParams: jest.fn().mockName('setUrlParams'),
}));

describe('Test reports app', () => {
  let wrapper;
  let pinia;
  let store;

  const loadingSpinner = () => wrapper.findComponent(GlLoadingIcon);
  const testsDetail = () => wrapper.findByTestId('tests-detail');
  const emptyState = () => wrapper.findComponent(EmptyState);
  const testSummaryTable = () => wrapper.findComponent(TestSummaryTable);
  const searchInput = () => wrapper.findComponentByTestId('test-cases-search');
  const backButton = () => wrapper.findComponent('.js-back-button');

  beforeEach(() => {
    getParameterValues.mockReturnValue([]);
  });

  const createComponent = ({ state = {}, glFeatures = {} } = {}) => {
    pinia = createTestingPinia();
    store = useTestReportsStore();
    Object.assign(store, { testReports, ...state });

    wrapper = extendedWrapper(
      shallowMount(TestReports, {
        pinia,
        provide: {
          glFeatures: {
            junitTestReportSearch: true,
            ...glFeatures,
          },
        },
      }),
    );
  };

  describe('when component is created', () => {
    it('should call fetchSummary when pipeline has test report', () => {
      createComponent();

      expect(store.fetchSummary).toHaveBeenCalled();
    });
  });

  describe('when loading', () => {
    beforeEach(() => createComponent({ state: { isLoading: true } }));

    it('shows the loading spinner', () => {
      expect(emptyState().exists()).toBe(false);
      expect(testsDetail().exists()).toBe(false);
      expect(loadingSpinner().exists()).toBe(true);
    });
  });

  describe('when the api returns no data', () => {
    it('displays empty state component', () => {
      createComponent({ state: { testReports: {} } });

      expect(emptyState().exists()).toBe(true);
    });
  });

  describe('when the api returns data', () => {
    beforeEach(() => createComponent());

    it('sets testReports and shows tests', () => {
      expect(wrapper.vm.testReports).toEqual(expect.any(Object));
      expect(wrapper.vm.showTests).toBe(true);
    });

    it('shows tests details', () => {
      expect(testsDetail().exists()).toBe(true);
    });

    it('renders the search input', () => {
      expect(searchInput().exists()).toBe(true);
    });
  });

  describe('when feature flag is disabled', () => {
    beforeEach(() => {
      createComponent({ glFeatures: { junitTestReportSearch: false } });
    });

    it('does not render the search input', () => {
      expect(searchInput().exists()).toBe(false);
    });
  });

  describe('when a job name is provided as a query parameter', () => {
    beforeEach(() => {
      getParameterValues.mockReturnValue(['javascript']);
      createComponent();
    });

    it('shows tests details', () => {
      expect(testsDetail().exists()).toBe(true);
    });

    it('should call setSelectedSuiteIndex and fetchTestSuite', () => {
      expect(store.setSelectedSuiteIndex).toHaveBeenCalled();
      expect(store.fetchTestSuite).toHaveBeenCalled();
    });
  });

  describe('when a suite is clicked', () => {
    beforeEach(() => {
      document.title = 'Test reports';
      createComponent();
      testSummaryTable().vm.$emit('row-click', 0);
    });

    it('should call setSelectedSuiteIndex, fetchTestSuite and updateHistory', () => {
      expect(store.setSelectedSuiteIndex).toHaveBeenCalledWith(0);
      expect(store.fetchTestSuite).toHaveBeenCalledWith(0);
      expect(setUrlParams).toHaveBeenCalledWith({ job_name: undefined });
      expect(updateHistory).toHaveBeenCalledWith({
        replace: true,
        title: 'Test reports',
        url: undefined,
      });
    });

    it('resets search scope to suite and clears search term', () => {
      expect(store.setSearchScope).toHaveBeenCalledWith(SEARCH_SCOPE_SUITE);
      expect(store.setSearchTerm).toHaveBeenCalledWith('');
    });
  });

  describe('when clicking back to summary', () => {
    beforeEach(() => {
      document.title = 'Test reports';
      createComponent({
        state: {
          selectedSuiteIndex: 0,
          pageInfo: {
            page: 3,
            perPage: 20,
          },
        },
      });
      backButton().vm.$emit('click');
    });

    it('should call removeSelectedSuiteIndex, updateHistory and setPage', () => {
      expect(store.removeSelectedSuiteIndex).toHaveBeenCalled();
      expect(removeParams).toHaveBeenCalledWith(['job_name']);
      expect(updateHistory).toHaveBeenCalledWith({
        replace: true,
        title: 'Test reports',
        url: undefined,
      });
      expect(store.setPage).toHaveBeenCalledWith(1);
    });

    it('should reset search scope to all and clear search term', () => {
      expect(store.setSearchScope).toHaveBeenCalledWith(SEARCH_SCOPE_ALL);
      expect(store.setSearchTerm).toHaveBeenCalledWith('');
    });
  });

  describe('search functionality', () => {
    describe('when searching from summary view', () => {
      beforeEach(() => {
        createComponent();
        searchInput().vm.$emit('input', 'mytest');
      });

      it('calls setSearchTerm with the input value', () => {
        expect(store.setSearchTerm).toHaveBeenCalledWith('mytest');
      });

      it('calls setSearchScope with "all"', () => {
        expect(store.setSearchScope).toHaveBeenCalledWith(SEARCH_SCOPE_ALL);
      });
    });

    describe('when searching from a drilled-in suite view', () => {
      beforeEach(() => {
        createComponent({ state: { selectedSuiteIndex: 0 } });
        searchInput().vm.$emit('input', 'mytest');
      });

      it('calls setSearchTerm with the input value', () => {
        expect(store.setSearchTerm).toHaveBeenCalledWith('mytest');
      });

      it('calls setSearchScope with "suite"', () => {
        expect(store.setSearchScope).toHaveBeenCalledWith(SEARCH_SCOPE_SUITE);
      });
    });

    describe('when searching from a drilled-in suite view and search scope is already "all"', () => {
      beforeEach(() => {
        createComponent({
          state: {
            selectedSuiteIndex: 0,
            searchScope: SEARCH_SCOPE_ALL,
          },
        });
        searchInput().vm.$emit('input', 'mytest');
      });

      it('does not reset search scope to "suite"', () => {
        expect(store.setSearchScope).toHaveBeenCalledWith(SEARCH_SCOPE_ALL);
      });
    });

    describe('when search term is empty', () => {
      describe('when in summary view', () => {
        beforeEach(() => {
          createComponent({ state: { searchTerm: 'existing' } });
          searchInput().vm.$emit('input', '');
        });

        it('calls setSearchTerm with an empty string', () => {
          expect(store.setSearchTerm).toHaveBeenCalledWith('');
        });

        it('does not call setSearchScope', () => {
          expect(store.setSearchScope).not.toHaveBeenCalled();
        });
      });

      describe('when in drilled-in suite view', () => {
        beforeEach(() => {
          createComponent({ state: { selectedSuiteIndex: 0, searchTerm: 'existing' } });
          searchInput().vm.$emit('input', '');
        });

        it('calls setSearchTerm with an empty string', () => {
          expect(store.setSearchTerm).toHaveBeenCalledWith('');
        });

        it('resets search scope to suite', () => {
          expect(store.setSearchScope).toHaveBeenCalledWith(SEARCH_SCOPE_SUITE);
        });
      });
    });
  });
});
