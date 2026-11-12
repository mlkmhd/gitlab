import MockAdapter from 'axios-mock-adapter';
import { cloneDeep } from 'lodash-es';
import { createTestingPinia } from '@pinia/testing';
import testReportsFixture from 'test_fixtures/pipelines/test_report.json';
import { TEST_HOST } from 'helpers/test_constants';
import { createAlert } from '~/alert';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_OK, HTTP_STATUS_INTERNAL_SERVER_ERROR } from '~/lib/utils/http_status';
import { useTestReportsStore } from '~/ci/pipeline_details/stores/test_reports';
import {
  iconForTestStatus,
  formatFilePath,
  formattedTime,
} from '~/ci/pipeline_details/stores/test_reports/utils';
import {
  ARTIFACTS_EXPIRED_ERROR_MESSAGE,
  SEARCH_SCOPE_SUITE,
  SEARCH_SCOPE_ALL,
} from '~/ci/pipeline_details/stores/test_reports/constants';

jest.mock('~/alert');

describe('TestReports store', () => {
  let mock;
  let store;
  let testReports;

  const blobPath = '/test/blob/path';
  const suiteEndpoint = `${TEST_HOST}/tests/suite.json`;
  const summaryEndpoint = `${TEST_HOST}/test_reports/summary.json`;

  beforeEach(() => {
    mock = new MockAdapter(axios);
    testReports = cloneDeep(testReportsFixture);
    createTestingPinia({ stubActions: false });
    store = useTestReportsStore();
    store.setInitialState({ blobPath, summaryEndpoint, suiteEndpoint });
  });

  afterEach(() => {
    mock.restore();
  });

  describe('setInitialState', () => {
    it('seeds the endpoints and blob path', () => {
      expect(store.blobPath).toBe(blobPath);
      expect(store.summaryEndpoint).toBe(summaryEndpoint);
      expect(store.suiteEndpoint).toBe(suiteEndpoint);
    });

    it('resets state left over from a previous mount', () => {
      store.searchTerm = 'stale';
      store.selectedSuiteIndex = 2;

      store.setInitialState({ blobPath, summaryEndpoint, suiteEndpoint });

      expect(store.searchTerm).toBe('');
      expect(store.selectedSuiteIndex).toBe(null);
      expect(store.blobPath).toBe(blobPath);
    });

    it('defaults the rest of the state', () => {
      expect(store.testReports).toEqual({});
      expect(store.selectedSuiteIndex).toBe(null);
      expect(store.isLoading).toBe(false);
      expect(store.searchTerm).toBe('');
      expect(store.searchScope).toBe(SEARCH_SCOPE_SUITE);
      expect(store.pageInfo).toEqual({ page: 1, perPage: 20 });
    });
  });

  describe('actions', () => {
    describe('fetchSummary', () => {
      const summary = {
        total: { time: 0, count: 10, success: 1, failed: 2, skipped: 3, error: 4 },
      };

      it('maps the summary totals onto testReports', async () => {
        mock.onGet(summaryEndpoint).replyOnce(HTTP_STATUS_OK, summary);

        await store.fetchSummary();

        expect(store.testReports).toEqual({
          ...summary,
          total_time: 0,
          total_count: 10,
          success_count: 1,
          failed_count: 2,
          skipped_count: 3,
          error_count: 4,
        });
      });

      it('is loading while the request is in flight', () => {
        mock.onGet(summaryEndpoint).replyOnce(HTTP_STATUS_OK, summary);

        const request = store.fetchSummary();

        expect(store.isLoading).toBe(true);
        return request.then(() => expect(store.isLoading).toBe(false));
      });

      it('creates an alert on API error', async () => {
        mock.onGet(summaryEndpoint).replyOnce(HTTP_STATUS_INTERNAL_SERVER_ERROR);

        await store.fetchSummary();

        expect(createAlert).toHaveBeenCalledWith({
          message: 'There was an error fetching the summary.',
        });
        expect(store.isLoading).toBe(false);
      });
    });

    describe('fetchTestSuite', () => {
      const buildIds = [1];

      beforeEach(() => {
        testReports.test_suites[0].build_ids = buildIds;
        store.testReports = testReports;
      });

      it('stores the suite at the given index and marks it as fully loaded', async () => {
        const suite = { name: 'test_suite', test_cases: [] };
        mock
          .onGet(suiteEndpoint, { params: { build_ids: buildIds } })
          .replyOnce(HTTP_STATUS_OK, suite);

        await store.fetchTestSuite(0);

        expect(store.testReports.test_suites[0]).toEqual({ ...suite, hasFullSuite: true });
        expect(store.isLoading).toBe(false);
      });

      it('updates getters that were read before the suite loaded', async () => {
        const testCase = { name: 'loaded case', classname: 'spec', status: 'success' };
        mock.onGet(suiteEndpoint).replyOnce(HTTP_STATUS_OK, { test_cases: [testCase] });
        store.selectedSuiteIndex = 0;
        store.testReports.test_suites[0].test_cases = undefined;

        expect(store.getSuiteTestCount).toBe(0);

        await store.fetchTestSuite(0);

        expect(store.getSuiteTestCount).toBe(1);
      });

      it('sets the error message when the API returns one', async () => {
        mock.onGet(suiteEndpoint).replyOnce(HTTP_STATUS_INTERNAL_SERVER_ERROR, {
          errors: ARTIFACTS_EXPIRED_ERROR_MESSAGE,
        });

        await store.fetchTestSuite(0);

        expect(store.errorMessage).toBe(ARTIFACTS_EXPIRED_ERROR_MESSAGE);
        expect(createAlert).not.toHaveBeenCalled();
      });

      it('creates an alert when the API returns no error message', async () => {
        mock.onGet(suiteEndpoint).replyOnce(HTTP_STATUS_INTERNAL_SERVER_ERROR);

        await store.fetchTestSuite(0);

        expect(createAlert).toHaveBeenCalledWith({
          message: 'There was an error fetching the test suite.',
        });
        expect(store.isLoading).toBe(false);
      });

      describe('when we already have the suite data', () => {
        it('does not fetch the suite', async () => {
          store.testReports.test_suites[0].hasFullSuite = true;

          await store.fetchTestSuite(0);

          expect(mock.history.get).toHaveLength(0);
          expect(store.isLoading).toBe(false);
        });
      });
    });

    describe('fetchAllSuites', () => {
      let suite0;
      let suite1;

      beforeEach(() => {
        suite0 = { name: 'rspec unit', hasFullSuite: false, build_ids: [1] };
        suite1 = { name: 'jest unit', hasFullSuite: false, build_ids: [2] };
        store.testReports = { test_suites: [suite0, suite1] };
      });

      it('fetches every suite and marks them as fully loaded', async () => {
        mock
          .onGet(suiteEndpoint, { params: { build_ids: [1] } })
          .replyOnce(HTTP_STATUS_OK, suite0)
          .onGet(suiteEndpoint, { params: { build_ids: [2] } })
          .replyOnce(HTTP_STATUS_OK, suite1);

        const request = store.fetchAllSuites();

        expect(store.isLoadingAllSuites).toBe(true);

        await request;

        expect(store.testReports.test_suites).toEqual([
          { ...suite0, hasFullSuite: true },
          { ...suite1, hasFullSuite: true },
        ]);
        expect(store.hasFetchedAllSuites).toBe(true);
        expect(store.isLoadingAllSuites).toBe(false);
      });

      it('skips suites that are already fully loaded', async () => {
        store.testReports.test_suites[0].hasFullSuite = true;
        mock.onGet(suiteEndpoint, { params: { build_ids: [2] } }).replyOnce(HTTP_STATUS_OK, suite1);

        await store.fetchAllSuites();

        expect(mock.history.get).toHaveLength(1);
        expect(store.testReports.test_suites[1]).toEqual({ ...suite1, hasFullSuite: true });
      });

      describe('when every suite has already been fetched', () => {
        it('does nothing', async () => {
          store.hasFetchedAllSuites = true;

          await store.fetchAllSuites();

          expect(mock.history.get).toHaveLength(0);
        });
      });

      describe('while a fetch is already in progress', () => {
        it('does nothing', async () => {
          store.isLoadingAllSuites = true;

          await store.fetchAllSuites();

          expect(mock.history.get).toHaveLength(0);
        });
      });

      describe('when a suite fails to load', () => {
        beforeEach(() => {
          mock
            .onGet(suiteEndpoint, { params: { build_ids: [1] } })
            .replyOnce(HTTP_STATUS_OK, suite0)
            .onGet(suiteEndpoint, { params: { build_ids: [2] } })
            .replyOnce(HTTP_STATUS_INTERNAL_SERVER_ERROR);
        });

        it('keeps the summary-only entry for the failing suite and alerts the user', async () => {
          await store.fetchAllSuites();

          expect(store.testReports.test_suites).toEqual([
            { ...suite0, hasFullSuite: true },
            suite1,
          ]);
          expect(store.hasFetchedAllSuites).toBe(true);
          expect(store.isLoadingAllSuites).toBe(false);
          expect(createAlert).toHaveBeenCalledWith({
            message: 'Some test suites could not be loaded and are excluded from search results.',
          });
        });
      });
    });

    describe('setPage', () => {
      it('sets the current page to display', () => {
        store.setPage(3);

        expect(store.pageInfo.page).toBe(3);
      });
    });

    describe('setSelectedSuiteIndex', () => {
      it('sets selectedSuiteIndex', () => {
        store.setSelectedSuiteIndex(0);

        expect(store.selectedSuiteIndex).toBe(0);
      });
    });

    describe('removeSelectedSuiteIndex', () => {
      it('sets selectedSuiteIndex to null', () => {
        store.selectedSuiteIndex = 0;

        store.removeSelectedSuiteIndex();

        expect(store.selectedSuiteIndex).toBe(null);
      });
    });

    describe('toggleLoading', () => {
      it('toggles isLoading', () => {
        store.toggleLoading();
        expect(store.isLoading).toBe(true);

        store.toggleLoading();
        expect(store.isLoading).toBe(false);
      });
    });

    describe('setSearchTerm', () => {
      it('sets searchTerm and resets the current page', () => {
        store.pageInfo.page = 3;

        store.setSearchTerm('my test');

        expect(store.searchTerm).toBe('my test');
        expect(store.pageInfo.page).toBe(1);
      });
    });

    describe('setSearchScope', () => {
      it('sets searchScope and resets the current page', () => {
        store.pageInfo.page = 3;

        store.setSearchScope(SEARCH_SCOPE_ALL);

        expect(store.searchScope).toBe(SEARCH_SCOPE_ALL);
        expect(store.pageInfo.page).toBe(1);
      });
    });
  });

  describe('getters', () => {
    const allTestCases = () =>
      testReports.test_suites.flatMap((suite) =>
        suite.test_cases.map((testCase) => ({
          ...testCase,
          classname: testCase.classname || '',
          name: testCase.name || '',
          suiteName: suite.name,
          filePath: `${blobPath}/${formatFilePath(testCase.file)}`,
        })),
      );

    beforeEach(() => {
      Object.assign(store, {
        testReports,
        selectedSuiteIndex: 0,
        pageInfo: { page: 1, perPage: 2 },
      });
    });

    describe('getTestSuites', () => {
      it('returns the test suites with their formatted time', () => {
        expect(store.getTestSuites).toEqual(
          testReports.test_suites.map((x) => ({
            ...x,
            formattedTime: formattedTime(x.total_time),
          })),
        );
      });

      it('returns an empty array when testReports is empty', () => {
        store.testReports = {};

        expect(store.getTestSuites).toEqual([]);
      });
    });

    describe('getSelectedSuite', () => {
      it('returns the selected suite', () => {
        expect(store.getSelectedSuite).toEqual(testReports.test_suites[0]);
      });
    });

    describe('getSuiteTests', () => {
      const expectedCases = (testCases, overrides = {}) =>
        testCases
          .map((x) => ({
            ...x,
            ...overrides,
            filePath: `${blobPath}/${formatFilePath(x.file)}`,
            formattedTime: formattedTime(x.execution_time),
            icon: iconForTestStatus(x.status),
          }))
          .slice(0, 2);

      it('returns the current page of test cases inside the suite', () => {
        expect(store.getSuiteTests).toEqual(expectedCases(testReports.test_suites[0].test_cases));
      });

      it('returns an empty array when testReports is empty', () => {
        store.testReports = {};

        expect(store.getSuiteTests).toEqual([]);
      });

      it.each(['classname', 'name'])(
        'returns an empty string when a test case %s is null',
        (property) => {
          const testCases = testReports.test_suites[0].test_cases;
          store.testReports = {
            ...testReports,
            test_suites: [
              { test_cases: testCases.map((testCase) => ({ ...testCase, [property]: null })) },
            ],
          };

          expect(store.getSuiteTests).toEqual(expectedCases(testCases, { [property]: '' }));
        },
      );
    });

    describe('getSuiteTestCount', () => {
      it('returns the total number of test cases', () => {
        expect(store.getSuiteTestCount).toBe(testReports.test_suites[0].test_cases.length);
      });
    });

    describe('getSuiteArtifactsExpired', () => {
      it('returns true when errorMessage matches the artifacts-expired message', () => {
        store.errorMessage = ARTIFACTS_EXPIRED_ERROR_MESSAGE;

        expect(store.getSuiteArtifactsExpired).toBe(true);
      });

      it('returns false when errorMessage does not match', () => {
        store.errorMessage = null;

        expect(store.getSuiteArtifactsExpired).toBe(false);
      });
    });

    describe('getTotalSuiteCount', () => {
      it('returns the number of suites in the pipeline', () => {
        expect(store.getTotalSuiteCount).toBe(testReports.test_suites.length);
      });

      it('returns 0 when testReports is empty', () => {
        store.testReports = {};

        expect(store.getTotalSuiteCount).toBe(0);
      });
    });

    describe('isSearching', () => {
      it.each`
        searchTerm | expected
        ${''}      | ${false}
        ${'   '}   | ${false}
        ${'test'}  | ${true}
      `('returns $expected when searchTerm is "$searchTerm"', ({ searchTerm, expected }) => {
        store.searchTerm = searchTerm;

        expect(store.isSearching).toBe(expected);
      });
    });

    describe('getAllTestCases', () => {
      it("flattens every suite's test cases and tags each with its suite name", () => {
        expect(store.getAllTestCases).toEqual(allTestCases());
      });

      it('returns an empty array when testReports is empty', () => {
        store.testReports = {};

        expect(store.getAllTestCases).toEqual([]);
      });
    });

    describe('getFilteredTestCases', () => {
      it('searches across every suite when the scope is "all"', () => {
        store.searchScope = SEARCH_SCOPE_ALL;

        expect(store.getFilteredTestCases).toEqual(allTestCases());
      });

      it('limits results to the selected suite when the scope is "suite"', () => {
        store.searchScope = SEARCH_SCOPE_SUITE;

        expect(store.getFilteredTestCases).toEqual(
          allTestCases().filter(
            (testCase) => testCase.suiteName === testReports.test_suites[0].name,
          ),
        );
      });

      it('filters by the search term', () => {
        const [firstCase] = testReports.test_suites[0].test_cases;
        store.searchScope = SEARCH_SCOPE_ALL;
        store.searchTerm = firstCase.name;

        expect(store.getFilteredTestCases).toEqual(
          allTestCases().filter((testCase) => testCase.name === firstCase.name),
        );
      });
    });

    describe('getSearchResults', () => {
      it('paginates the filtered test cases and adds icon/time metadata', () => {
        store.searchScope = SEARCH_SCOPE_ALL;

        expect(store.getSearchResults).toEqual(
          allTestCases()
            .slice(0, 2)
            .map((testCase) => ({
              ...testCase,
              icon: iconForTestStatus(testCase.status),
              formattedTime: formattedTime(testCase.execution_time),
            })),
        );
      });
    });

    describe('getSearchResultsCount', () => {
      it('returns the total number of filtered test cases', () => {
        store.searchScope = SEARCH_SCOPE_ALL;

        expect(store.getSearchResultsCount).toBe(allTestCases().length);
      });
    });
  });
});
