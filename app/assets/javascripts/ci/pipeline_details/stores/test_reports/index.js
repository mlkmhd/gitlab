import { defineStore } from 'pinia';
import { createAlert } from '~/alert';
import axios from '~/lib/utils/axios_utils';
import { s__ } from '~/locale';
import { addIconStatus, filterTestCases, formatFilePath, formattedTime } from './utils';
import {
  ARTIFACTS_EXPIRED_ERROR_MESSAGE,
  SEARCH_SCOPE_SUITE,
  SUITE_FETCH_CONCURRENCY,
} from './constants';

const fetchSuiteCases = (suiteEndpoint, testReports, index) => {
  const { build_ids: buildIds = [] } = testReports?.test_suites?.[index] || {};

  return axios.get(suiteEndpoint, { params: { build_ids: buildIds } }).then(({ data }) => data);
};

export const useTestReportsStore = defineStore('testReports', {
  state() {
    return {
      blobPath: '',
      summaryEndpoint: '',
      suiteEndpoint: '',
      testReports: {},
      selectedSuiteIndex: null,
      isLoading: false,
      errorMessage: null,
      searchTerm: '',
      searchScope: SEARCH_SCOPE_SUITE,
      hasFetchedAllSuites: false,
      isLoadingAllSuites: false,
      pageInfo: {
        page: 1,
        perPage: 20,
      },
    };
  },
  getters: {
    getTestSuites() {
      const { test_suites: testSuites = [] } = this.testReports;

      return testSuites.map((suite) => ({
        ...suite,
        formattedTime: formattedTime(suite.total_time),
      }));
    },
    getSelectedSuite() {
      return this.testReports?.test_suites?.[this.selectedSuiteIndex] || {};
    },
    getSuiteTests() {
      const { test_cases: testCases = [] } = this.getSelectedSuite;
      const { page, perPage } = this.pageInfo;
      const start = (page - 1) * perPage;

      return testCases
        .map((testCase) => ({
          ...testCase,
          classname: testCase.classname || '',
          name: testCase.name || '',
          filePath: testCase.file ? `${this.blobPath}/${formatFilePath(testCase.file)}` : null,
        }))
        .map((testCase) => addIconStatus(testCase))
        .slice(start, start + perPage);
    },
    getSuiteTestCount() {
      return this.getSelectedSuite?.test_cases?.length || 0;
    },
    getSuiteArtifactsExpired() {
      return this.errorMessage === ARTIFACTS_EXPIRED_ERROR_MESSAGE;
    },
    getTotalSuiteCount() {
      return this.testReports?.test_suites?.length || 0;
    },
    isSearching() {
      return this.searchTerm.trim().length > 0;
    },
    getAllTestCases() {
      const { test_suites: testSuites = [] } = this.testReports;

      return testSuites.flatMap((suite) =>
        (suite.test_cases || []).map((testCase) => ({
          ...testCase,
          classname: testCase.classname || '',
          name: testCase.name || '',
          suiteName: suite.name,
          filePath: testCase.file ? `${this.blobPath}/${formatFilePath(testCase.file)}` : null,
        })),
      );
    },
    getFilteredTestCases() {
      const pool =
        this.searchScope === SEARCH_SCOPE_SUITE && this.selectedSuiteIndex !== null
          ? this.getAllTestCases.filter(
              (tc) =>
                tc.suiteName === this.testReports?.test_suites?.[this.selectedSuiteIndex]?.name,
            )
          : this.getAllTestCases;

      return filterTestCases(pool, this.searchTerm);
    },
    getSearchResults() {
      const { page, perPage } = this.pageInfo;
      const start = (page - 1) * perPage;

      return this.getFilteredTestCases
        .slice(start, start + perPage)
        .map((testCase) => addIconStatus(testCase));
    },
    getSearchResultsCount() {
      return this.getFilteredTestCases.length;
    },
  },
  actions: {
    setInitialState({ blobPath = '', summaryEndpoint = '', suiteEndpoint = '' } = {}) {
      this.$reset();
      this.blobPath = blobPath;
      this.summaryEndpoint = summaryEndpoint;
      this.suiteEndpoint = suiteEndpoint;
    },
    fetchSummary() {
      this.toggleLoading();

      return axios
        .get(this.summaryEndpoint)
        .then(({ data }) => {
          const { total } = data;
          this.testReports = {
            ...data,

            /*
              TLDR; this is a temporary mapping that will be updated once
              test suites have the new data schema

              The backend is in the middle of updating the data schema
              to have a `total` object containing the total data values.
              The test suites don't have the new schema, but the summary
              does. Currently the `test_summary.vue` component takes both
              the summary and a test suite depending on what is being viewed.
              This is a temporary change to map the new schema to the old until
              we can update the schema for the test suites also.
              Since test suites is an array, it is easier to just map the summary
              to the old schema instead of mapping every test suite to the new.
            */

            total_time: total.time,
            total_count: total.count,
            success_count: total.success,
            failed_count: total.failed,
            skipped_count: total.skipped,
            error_count: total.error,
          };
        })
        .catch(() => {
          createAlert({
            message: s__('TestReports|There was an error fetching the summary.'),
          });
        })
        .finally(() => {
          this.toggleLoading();
        });
    },
    fetchTestSuite(index) {
      const { hasFullSuite } = this.testReports?.test_suites?.[index] || {};
      // We don't need to fetch the suite if we have the information already
      if (hasFullSuite) {
        return Promise.resolve();
      }

      this.toggleLoading();

      return fetchSuiteCases(this.suiteEndpoint, this.testReports, index)
        .then((data) => {
          // Replace the array instead of writing one index, which Vue 2 doesn't detect.
          const testSuites = this.testReports.test_suites.slice();
          testSuites[index] = { ...data, hasFullSuite: true };
          this.testReports = { ...this.testReports, test_suites: testSuites };
        })
        .catch((error) => {
          const errorMessage = error.response?.data?.errors;

          if (errorMessage) {
            this.errorMessage = errorMessage;
          } else {
            createAlert({
              message: s__('TestReports|There was an error fetching the test suite.'),
            });
          }
        })
        .finally(() => {
          this.toggleLoading();
        });
    },
    // Loads every suite's test cases (once) so a global search can filter across
    // all jobs client-side. Suites already fully loaded are skipped, and requests
    // run with bounded concurrency to avoid a burst of one request per suite.
    fetchAllSuites() {
      if (this.hasFetchedAllSuites || this.isLoadingAllSuites) {
        return Promise.resolve();
      }

      const suites = this.testReports?.test_suites || [];
      const results = suites.slice();
      const queue = suites
        .map((suite, index) => index)
        .filter((index) => !suites[index].hasFullSuite);
      let hasSuiteFetchError = false;

      this.isLoadingAllSuites = true;

      const worker = () => {
        if (queue.length === 0) {
          return Promise.resolve();
        }

        const index = queue.shift();
        return fetchSuiteCases(this.suiteEndpoint, this.testReports, index)
          .then((data) => {
            results[index] = { ...data, hasFullSuite: true };
          })
          .catch(() => {
            // Leave the summary-only entry in place; its cases just won't be
            // searchable. A single failing suite must not break the whole search.
            hasSuiteFetchError = true;
          })
          .then(worker);
      };

      const workers = Array.from(
        { length: Math.min(SUITE_FETCH_CONCURRENCY, queue.length) },
        worker,
      );

      return Promise.all(workers)
        .then(() => {
          // Reassign the whole array (rather than mutating indices) so the change is
          // reactive and the global search getters recompute once loading finishes.
          this.testReports = { ...this.testReports, test_suites: results };
          this.hasFetchedAllSuites = true;

          if (hasSuiteFetchError) {
            createAlert({
              message: s__(
                'TestReports|Some test suites could not be loaded and are excluded from search results.',
              ),
            });
          }
        })
        .catch(() => {
          createAlert({
            message: s__('TestReports|There was an error fetching the test cases.'),
          });
        })
        .finally(() => {
          this.isLoadingAllSuites = false;
        });
    },
    setSearchTerm(searchTerm) {
      this.searchTerm = searchTerm;
      // Any change to the filter invalidates the current page.
      this.pageInfo = { ...this.pageInfo, page: 1 };
    },
    setSearchScope(scope) {
      this.searchScope = scope;
      this.pageInfo = { ...this.pageInfo, page: 1 };
    },
    setPage(page) {
      this.pageInfo.page = page;
    },
    setSelectedSuiteIndex(selectedSuiteIndex) {
      this.selectedSuiteIndex = selectedSuiteIndex;
    },
    removeSelectedSuiteIndex() {
      this.selectedSuiteIndex = null;
    },
    toggleLoading() {
      this.isLoading = !this.isLoading;
    },
  },
});
