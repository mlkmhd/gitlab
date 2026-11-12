import MockAdapter from 'axios-mock-adapter';
import { createTestingPinia } from '@pinia/testing';
import { LICENSE_APPROVAL_STATUS } from 'ee/vue_shared/license_compliance/constants';
import { useLicenseManagement } from 'ee/vue_shared/license_compliance/store';
import waitForPromises from 'helpers/wait_for_promises';
import { TEST_HOST } from 'spec/test_constants';
import axios from '~/lib/utils/axios_utils';
import {
  HTTP_STATUS_BAD_REQUEST,
  HTTP_STATUS_INTERNAL_SERVER_ERROR,
  HTTP_STATUS_OK,
} from '~/lib/utils/http_status';
import { allowedLicense, licenseReport as licenseReportMock } from '../mock_data';

describe('License store', () => {
  const apiUrlManageLicenses = `${TEST_HOST}/licenses/management`;
  const approvalsApiPath = `${TEST_HOST}/approvalsApiPath`;
  const licensesApiPath = `${TEST_HOST}/licensesApiPath`;

  let store;
  let axiosMock;

  beforeEach(() => {
    createTestingPinia({ stubActions: false });
    store = useLicenseManagement();
    axiosMock = new MockAdapter(axios);
  });

  afterEach(() => {
    axiosMock.restore();
  });

  describe('actions', () => {
    describe('setAPISettings', () => {
      it('assigns data to the store', () => {
        store.setAPISettings({ apiUrlManageLicenses: TEST_HOST });

        expect(store.apiUrlManageLicenses).toBe(TEST_HOST);
      });
    });

    describe('requestManagedLicenses', () => {
      it('sets isLoadingManagedLicenses to true', () => {
        store.isLoadingManagedLicenses = false;

        store.requestManagedLicenses();

        expect(store.isLoadingManagedLicenses).toBe(true);
      });
    });

    describe('receiveManagedLicensesSuccess', () => {
      it('sets isLoadingManagedLicenses to false and saves managed licenses', () => {
        store.managedLicenses = false;
        store.isLoadingManagedLicenses = true;

        store.receiveManagedLicensesSuccess([
          { name: 'Foo', approval_status: LICENSE_APPROVAL_STATUS.approved },
        ]);

        expect(store.managedLicenses).toEqual([
          { name: 'Foo', approvalStatus: LICENSE_APPROVAL_STATUS.approved },
        ]);
        expect(store.isLoadingManagedLicenses).toBe(false);
      });

      it('saves the licenses in reverse order', () => {
        store.receiveManagedLicensesSuccess([
          { name: 'Foo', approval_status: LICENSE_APPROVAL_STATUS.ALLOWED },
          { name: 'Bar', approval_status: LICENSE_APPROVAL_STATUS.DENIED },
        ]);

        expect(store.managedLicenses.map(({ name }) => name)).toEqual(['Bar', 'Foo']);
      });

      it('defaults to no licenses', () => {
        store.managedLicenses = [allowedLicense];

        store.receiveManagedLicensesSuccess();

        expect(store.managedLicenses).toEqual([]);
      });
    });

    describe('receiveManagedLicensesError', () => {
      it('sets isLoadingManagedLicenses to false and clears the managed licenses', () => {
        store.managedLicenses = [allowedLicense];
        store.isLoadingManagedLicenses = true;

        store.receiveManagedLicensesError(new Error('Test'));

        expect(store.isLoadingManagedLicenses).toBe(false);
        expect(store.managedLicenses).toEqual([]);
      });
    });

    describe('fetchManagedLicenses', () => {
      let endpointMock;

      beforeEach(() => {
        store.apiUrlManageLicenses = apiUrlManageLicenses;
        store.approvalsApiPath = approvalsApiPath;
        endpointMock = axiosMock.onGet(apiUrlManageLicenses, { params: { per_page: 100 } });
      });

      it('calls requestManagedLicenses and receiveManagedLicensesSuccess for successful response', async () => {
        const payload = [{ name: 'foo', approval_status: LICENSE_APPROVAL_STATUS.DENIED }];
        endpointMock.replyOnce(() => [HTTP_STATUS_OK, payload]);
        jest.spyOn(store, 'requestManagedLicenses');
        jest.spyOn(store, 'receiveManagedLicensesSuccess');
        jest.spyOn(store, 'receiveManagedLicensesError');

        await store.fetchManagedLicenses();

        expect(store.requestManagedLicenses).toHaveBeenCalledTimes(1);
        expect(store.receiveManagedLicensesSuccess).toHaveBeenCalledWith(payload);
        expect(store.receiveManagedLicensesError).not.toHaveBeenCalled();
        expect(store.managedLicenses).toEqual([
          { name: 'foo', approvalStatus: LICENSE_APPROVAL_STATUS.DENIED },
        ]);
        expect(store.isLoadingManagedLicenses).toBe(false);
      });

      it('calls requestManagedLicenses and receiveManagedLicensesError for error response', async () => {
        endpointMock.replyOnce(() => [HTTP_STATUS_INTERNAL_SERVER_ERROR, '']);
        jest.spyOn(store, 'requestManagedLicenses');
        jest.spyOn(store, 'receiveManagedLicensesSuccess');
        jest.spyOn(store, 'receiveManagedLicensesError');

        await store.fetchManagedLicenses();

        expect(store.requestManagedLicenses).toHaveBeenCalledTimes(1);
        expect(store.receiveManagedLicensesSuccess).not.toHaveBeenCalled();
        expect(store.receiveManagedLicensesError).toHaveBeenCalledTimes(1);
        expect(store.managedLicenses).toEqual([]);
        expect(store.isLoadingManagedLicenses).toBe(false);
      });
    });

    describe('requestParsedLicenseReport', () => {
      it('should initiate loading', () => {
        store.isLoadingLicenseReport = false;

        store.requestParsedLicenseReport();

        expect(store.isLoadingLicenseReport).toBe(true);
      });
    });

    describe('receiveParsedLicenseReportSuccess', () => {
      const newLicenses = [];
      const existingLicenses = [];

      beforeEach(() => {
        store.isLoadingLicenseReport = true;
        store.loadLicenseReportError = new Error('test');

        store.receiveParsedLicenseReportSuccess({ newLicenses, existingLicenses });
      });

      it('should set the new and existing reports', () => {
        expect(store.newLicenses).toStrictEqual(newLicenses);
        expect(store.existingLicenses).toStrictEqual(existingLicenses);
      });

      it('should cancel loading and clear any errors', () => {
        expect(store.isLoadingLicenseReport).toBe(false);
        expect(store.loadLicenseReportError).toBe(false);
      });
    });

    describe('receiveParsedLicenseReportError', () => {
      const error = new Error('test');

      beforeEach(() => {
        store.isLoadingLicenseReport = true;
        store.loadLicenseReportError = false;

        store.receiveParsedLicenseReportError(error);
      });

      it('should set the error on the state', () => {
        expect(store.loadLicenseReportError).toBe(error);
      });

      it('should cancel loading', () => {
        expect(store.isLoadingLicenseReport).toBe(false);
      });
    });

    describe('fetchParsedLicenseReport', () => {
      let licensesApiMock;
      let rawLicenseReport;

      beforeEach(() => {
        store.licensesApiPath = licensesApiPath;
        licensesApiMock = axiosMock.onGet(licensesApiPath);
      });

      describe('pipeline reports', () => {
        beforeEach(() => {
          rawLicenseReport = [
            {
              name: 'MIT',
              classification: {
                id: 2,
                approval_status: LICENSE_APPROVAL_STATUS.DENIED,
                name: 'MIT',
              },
              dependencies: [{ name: 'vue' }],
              count: 1,
              url: 'http://opensource.org/licenses/mit-license',
            },
          ];
        });

        it('should fetch, parse, and call the success action with the new licenses on a successful request', async () => {
          licensesApiMock.replyOnce(() => [HTTP_STATUS_OK, rawLicenseReport]);
          jest.spyOn(store, 'requestParsedLicenseReport');
          jest.spyOn(store, 'receiveParsedLicenseReportSuccess');

          const parsedLicenses = {
            existingLicenses: [],
            newLicenses: [
              {
                ...rawLicenseReport[0],
                id: 2,
                approvalStatus: LICENSE_APPROVAL_STATUS.DENIED,
                packages: [{ name: 'vue' }],
                status: 'failed',
              },
            ],
          };

          store.fetchParsedLicenseReport();
          await waitForPromises();

          expect(store.requestParsedLicenseReport).toHaveBeenCalledTimes(1);
          expect(store.receiveParsedLicenseReportSuccess).toHaveBeenCalledWith(parsedLicenses);
          expect(store.newLicenses).toEqual(parsedLicenses.newLicenses);
          expect(store.existingLicenses).toEqual([]);
          expect(store.isLoadingLicenseReport).toBe(false);
        });

        it('should call the error action on an unsuccessful request', async () => {
          licensesApiMock.replyOnce(HTTP_STATUS_BAD_REQUEST);
          jest.spyOn(store, 'requestParsedLicenseReport');
          jest.spyOn(store, 'receiveParsedLicenseReportSuccess');
          jest.spyOn(store, 'receiveParsedLicenseReportError');

          store.fetchParsedLicenseReport();
          await waitForPromises();

          expect(store.requestParsedLicenseReport).toHaveBeenCalledTimes(1);
          expect(store.receiveParsedLicenseReportSuccess).not.toHaveBeenCalled();
          expect(store.receiveParsedLicenseReportError).toHaveBeenCalledWith(expect.any(Error));
          expect(store.loadLicenseReportError).toEqual(expect.any(Error));
          expect(store.isLoadingLicenseReport).toBe(false);
        });
      });

      describe('MR widget reports', () => {
        beforeEach(() => {
          rawLicenseReport = {
            new_licenses: [
              {
                name: 'Apache 2.0',
                classification: {
                  id: 1,
                  approval_status: LICENSE_APPROVAL_STATUS.ALLOWED,
                  name: 'Apache 2.0',
                },
                dependencies: [{ name: 'echarts' }],
                count: 1,
                url: 'http://www.apache.org/licenses/LICENSE-2.0.txt',
              },
              {
                name: 'New BSD',
                classification: { id: 3, approval_status: 'unclassified', name: 'New BSD' },
                dependencies: [{ name: 'zrender' }],
                count: 1,
                url: 'http://opensource.org/licenses/BSD-3-Clause',
              },
            ],
            existing_licenses: [
              {
                name: 'MIT',
                classification: {
                  id: 2,
                  approval_status: LICENSE_APPROVAL_STATUS.DENIED,
                  name: 'MIT',
                },
                dependencies: [{ name: 'vue' }],
                count: 1,
                url: 'http://opensource.org/licenses/mit-license',
              },
            ],
            removed_licenses: [],
          };
        });

        it('should fetch, parse, and call the success action with the new licenses on a successful request', async () => {
          licensesApiMock.replyOnce(() => [HTTP_STATUS_OK, rawLicenseReport]);
          jest.spyOn(store, 'requestParsedLicenseReport');
          jest.spyOn(store, 'receiveParsedLicenseReportSuccess');

          const parsedLicenses = {
            existingLicenses: [
              {
                ...rawLicenseReport.existing_licenses[0],
                id: 2,
                approvalStatus: LICENSE_APPROVAL_STATUS.DENIED,
                packages: [{ name: 'vue' }],
                status: 'failed',
              },
            ],
            newLicenses: [
              {
                ...rawLicenseReport.new_licenses[0],
                id: 1,
                approvalStatus: LICENSE_APPROVAL_STATUS.ALLOWED,
                packages: [{ name: 'echarts' }],
                status: 'success',
              },
              {
                ...rawLicenseReport.new_licenses[1],
                id: 3,
                approvalStatus: 'unclassified',
                packages: [{ name: 'zrender' }],
                status: 'neutral',
              },
            ],
          };

          store.fetchParsedLicenseReport();
          await waitForPromises();

          expect(store.requestParsedLicenseReport).toHaveBeenCalledTimes(1);
          expect(store.receiveParsedLicenseReportSuccess).toHaveBeenCalledWith(parsedLicenses);
          expect(store.newLicenses).toEqual(parsedLicenses.newLicenses);
          expect(store.existingLicenses).toEqual(parsedLicenses.existingLicenses);
        });
      });
    });
  });

  describe('getters', () => {
    describe('isLoading', () => {
      it('is true if `isLoadingManagedLicenses` is true OR `isLoadingLicenseReport` is true', () => {
        store.isLoadingManagedLicenses = true;
        store.isLoadingLicenseReport = true;

        expect(store.isLoading).toBe(true);

        store.isLoadingManagedLicenses = false;
        store.isLoadingLicenseReport = true;

        expect(store.isLoading).toBe(true);

        store.isLoadingManagedLicenses = true;
        store.isLoadingLicenseReport = false;

        expect(store.isLoading).toBe(true);

        store.isLoadingManagedLicenses = false;
        store.isLoadingLicenseReport = false;

        expect(store.isLoading).toBe(false);
      });

      it('is true if `isLoadingLicenseCheckApprovalRule` is true', () => {
        store.isLoadingLicenseCheckApprovalRule = true;

        expect(store.isLoading).toBe(true);
      });
    });

    describe('isLicenseBeingUpdated', () => {
      it('is true only for ids of pending licenses', () => {
        store.pendingLicenses = [1];

        expect(store.isLicenseBeingUpdated(1)).toBe(true);
        expect(store.isLicenseBeingUpdated(2)).toBe(false);
        expect(store.isLicenseBeingUpdated()).toBe(false);
      });
    });

    describe('licenseReport', () => {
      it('should return the new licenses from the state', () => {
        const newLicenses = [{ test: 'foo' }];
        store.newLicenses = newLicenses;

        expect(store.licenseReport).toStrictEqual(newLicenses);
      });
    });

    describe('licenseReportGroups', () => {
      it('returns an array of objects containing information about the group and licenses', () => {
        const licensesSuccess = [
          { status: 'success', value: 'foo' },
          { status: 'success', value: 'bar' },
        ];
        const licensesNeutral = [
          { status: 'neutral', value: 'foo' },
          { status: 'neutral', value: 'bar' },
        ];
        const licensesFailed = [
          { status: 'failed', value: 'foo' },
          { status: 'failed', value: 'bar' },
        ];
        store.newLicenses = [...licensesSuccess, ...licensesNeutral, ...licensesFailed];

        expect(store.licenseReportGroups).toEqual([
          {
            name: 'Denied',
            description: `Out-of-compliance with this project's policies and should be removed`,
            status: 'failed',
            licenses: licensesFailed,
          },
          {
            name: 'Uncategorized',
            description: 'No policy matches this license',
            status: 'neutral',
            licenses: licensesNeutral,
          },
          {
            name: 'Allowed',
            description: 'Acceptable for use in this project',
            status: 'success',
            licenses: licensesSuccess,
          },
        ]);
      });

      it.each(['failed', 'neutral', 'success'])(
        `filters report-groups that don't have the given status: %s`,
        (status) => {
          const newLicenses = [{ status }];
          store.newLicenses = newLicenses;

          expect(store.licenseReportGroups).toEqual([
            expect.objectContaining({
              status,
              licenses: newLicenses,
            }),
          ]);
        },
      );
    });

    describe('hasReportItems', () => {
      it('is true if the report has licenses', () => {
        store.newLicenses = [licenseReportMock[0]];

        expect(store.hasReportItems).toBe(true);
      });

      it('is false if the report is empty', () => {
        store.newLicenses = [];

        expect(store.hasReportItems).toBe(false);
      });
    });

    describe('baseReportHasLicenses', () => {
      it('is true if there are existing licenses', () => {
        store.existingLicenses = [licenseReportMock[0]];

        expect(store.baseReportHasLicenses).toBe(true);
      });

      it('is false if there are no existing licenses', () => {
        store.existingLicenses = [];

        expect(store.baseReportHasLicenses).toBe(false);
      });
    });

    describe('licenseReportLength', () => {
      it('is the number of new licenses', () => {
        store.newLicenses = [licenseReportMock[0], licenseReportMock[0]];

        expect(store.licenseReportLength).toBe(2);
      });
    });

    describe('licenseSummaryText', () => {
      beforeEach(() => {
        store.loadLicenseReportError = null;
        store.newLicenses = [{ ...licenseReportMock[0] }];
        store.existingLicenses = [{ ...licenseReportMock[0] }];
      });

      it('should be `Loading License compliance report` text if isLoading', () => {
        store.isLoadingLicenseReport = true;

        expect(store.licenseSummaryText).toBe('Loading License compliance report');
      });

      it('should be `Failed to load License compliance report` text if an error has happened', () => {
        store.loadLicenseReportError = new Error('Test');

        expect(store.licenseSummaryText).toBe('Failed to load License compliance report');
      });

      it('should use the license check summary if new license are detected and license-check approval group is enabled', () => {
        store.hasLicenseCheckApprovalRule = true;
        store.newLicenses = [
          { ...licenseReportMock[0], approvalStatus: LICENSE_APPROVAL_STATUS.DENIED },
        ];

        expect(store.licenseSummaryText).toBe(store.summaryTextWithLicenseCheck);
        expect(store.licenseSummaryText).toBe(
          'License compliance detected 1 new license and policy violation; approval required',
        );
      });

      it('should use the summary without license check if new license are detected and license-check approval group is disabled', () => {
        store.hasLicenseCheckApprovalRule = false;
        store.newLicenses = [
          { ...licenseReportMock[0], approvalStatus: LICENSE_APPROVAL_STATUS.DENIED },
        ];

        expect(store.licenseSummaryText).toBe(store.summaryTextWithoutLicenseCheck);
        expect(store.licenseSummaryText).toBe(
          'License compliance detected 1 new license and policy violation',
        );
      });

      it('should show "License compliance detected no licenses for the source branch only" if there are no existing licenses', () => {
        store.newLicenses = [];
        store.existingLicenses = [];

        expect(store.licenseSummaryText).toBe(
          'License compliance detected no licenses for the source branch only',
        );
      });

      it('should show "License compliance detected no new licenses" if there are no new licenses, but existing licenses', () => {
        store.newLicenses = [];

        expect(store.licenseSummaryText).toBe('License compliance detected no new licenses');
      });
    });

    describe.each(['summaryTextWithLicenseCheck', 'summaryTextWithoutLicenseCheck'])(
      '%s',
      (getter) => {
        const withLicenseCheck = getter === 'summaryTextWithLicenseCheck';
        const approvalSuffix = withLicenseCheck ? '; approval required' : '';

        const setReport = ({ denied, baseHasLicenses, length }) => {
          const approvalStatus = denied
            ? LICENSE_APPROVAL_STATUS.DENIED
            : LICENSE_APPROVAL_STATUS.ALLOWED;

          store.newLicenses = Array.from({ length }, () => ({
            ...licenseReportMock[0],
            approvalStatus,
          }));
          store.existingLicenses = baseHasLicenses ? [licenseReportMock[0]] : [];
        };

        describe('when licenses exist on both the HEAD and the BASE', () => {
          describe('when denied licenses exist on the HEAD', () => {
            it('returns the singular text when a single license is detected', () => {
              setReport({ denied: true, baseHasLicenses: true, length: 1 });

              expect(store[getter]).toBe(
                `License compliance detected 1 new license and policy violation${approvalSuffix}`,
              );
            });

            it('returns the plural text when multiple licenses are detected', () => {
              setReport({ denied: true, baseHasLicenses: true, length: 2 });

              expect(store[getter]).toBe(
                `License compliance detected 2 new licenses and policy violations${approvalSuffix}`,
              );
            });
          });

          describe('when denied licenses are not detected on the HEAD', () => {
            it('returns the singular text when a single license is detected', () => {
              setReport({ denied: false, baseHasLicenses: true, length: 1 });

              expect(store[getter]).toBe('License compliance detected 1 new license');
            });

            it('returns the plural text when multiple licenses are detected', () => {
              setReport({ denied: false, baseHasLicenses: true, length: 2 });

              expect(store[getter]).toBe('License compliance detected 2 new licenses');
            });
          });
        });

        describe('when there are no licenses on the BASE', () => {
          describe('when denied licenses exist on the HEAD', () => {
            it('returns the singular text when a single license is detected', () => {
              setReport({ denied: true, baseHasLicenses: false, length: 1 });

              expect(store[getter]).toBe(
                `License compliance detected 1 license and policy violation${
                  withLicenseCheck ? ' for the source branch only' : ''
                }${approvalSuffix}`,
              );
            });

            it('returns the plural text when multiple licenses are detected', () => {
              setReport({ denied: true, baseHasLicenses: false, length: 2 });

              expect(store[getter]).toBe(
                `License compliance detected 2 licenses and policy violations${
                  withLicenseCheck ? ' for the source branch only' : ''
                }${approvalSuffix}`,
              );
            });
          });

          describe('when denied licenses are not detected on the HEAD', () => {
            it('returns the singular text when a single license is detected', () => {
              setReport({ denied: false, baseHasLicenses: false, length: 1 });

              expect(store[getter]).toBe(
                `License compliance detected 1 license${
                  withLicenseCheck ? ' for the source branch only' : ''
                }`,
              );
            });

            it('returns the plural text when multiple licenses are detected', () => {
              setReport({ denied: false, baseHasLicenses: false, length: 2 });

              expect(store[getter]).toBe(
                `License compliance detected 2 licenses${
                  withLicenseCheck ? ' for the source branch only' : ''
                }`,
              );
            });
          });
        });
      },
    );

    describe('reportContainsDeniedLicense', () => {
      it('should be false if the report does not contain denied licenses', () => {
        store.newLicenses = [licenseReportMock[0], licenseReportMock[0]];

        expect(store.reportContainsDeniedLicense).toBe(false);
      });

      it('should be true if the report contains denied licenses', () => {
        store.newLicenses = [
          licenseReportMock[0],
          { ...licenseReportMock[0], approvalStatus: LICENSE_APPROVAL_STATUS.DENIED },
        ];

        expect(store.reportContainsDeniedLicense).toBe(true);
      });
    });
  });
});
