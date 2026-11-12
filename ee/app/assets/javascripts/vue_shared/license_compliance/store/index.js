import { defineStore } from 'pinia';
import { LICENSE_APPROVAL_STATUS, REPORT_GROUPS } from 'ee/vue_shared/license_compliance/constants';
import axios from '~/lib/utils/axios_utils';
import pollUntilComplete from '~/lib/utils/poll_until_complete';
import { __, n__, s__, sprintf } from '~/locale';
import {
  addLicensesMatchingReportGroupStatus,
  convertToOldReportFormat,
  normalizeLicense,
  reportGroupHasAtLeastOneLicense,
} from './utils';

export const useLicenseManagement = defineStore('licenseManagement', {
  state() {
    return {
      apiUrlManageLicenses: null,
      approvalsApiPath: null,
      licensesApiPath: null,
      canManageLicenses: false,
      isLoadingLicenseReport: false,
      isLoadingManagedLicenses: false,
      pendingLicenses: [],
      loadLicenseReportError: false,
      managedLicenses: [],
      newLicenses: [],
      existingLicenses: [],
      hasLicenseCheckApprovalRule: false,
      isLoadingLicenseCheckApprovalRule: false,
    };
  },
  getters: {
    isLoading() {
      return (
        this.isLoadingManagedLicenses ||
        this.isLoadingLicenseReport ||
        this.isLoadingLicenseCheckApprovalRule
      );
    },
    isLicenseBeingUpdated() {
      return (id = null) => this.pendingLicenses.includes(id);
    },
    licenseReport() {
      return this.newLicenses;
    },
    licenseReportGroups() {
      return REPORT_GROUPS.map(addLicensesMatchingReportGroupStatus(this.newLicenses)).filter(
        (group) => reportGroupHasAtLeastOneLicense(group),
      );
    },
    hasReportItems() {
      return Boolean(this.licenseReportLength);
    },
    baseReportHasLicenses() {
      return Boolean(this.existingLicenses.length);
    },
    licenseReportLength() {
      return this.licenseReport.length;
    },
    licenseSummaryText() {
      if (this.isLoading) {
        return sprintf(s__('ciReport|Loading %{reportName} report'), {
          reportName: __('License compliance'),
        });
      }

      if (this.loadLicenseReportError) {
        return sprintf(s__('ciReport|Failed to load %{reportName} report'), {
          reportName: __('License compliance'),
        });
      }

      if (this.hasReportItems) {
        return this.hasLicenseCheckApprovalRule
          ? this.summaryTextWithLicenseCheck
          : this.summaryTextWithoutLicenseCheck;
      }

      if (!this.baseReportHasLicenses) {
        return s__(
          'LicenseCompliance|License compliance detected no licenses for the source branch only',
        );
      }

      return s__('LicenseCompliance|License compliance detected no new licenses');
    },
    summaryTextWithLicenseCheck() {
      if (!this.baseReportHasLicenses) {
        return this.reportContainsDeniedLicense
          ? n__(
              'LicenseCompliance|License compliance detected %d license and policy violation for the source branch only; approval required',
              'LicenseCompliance|License compliance detected %d licenses and policy violations for the source branch only; approval required',
              this.licenseReportLength,
            )
          : n__(
              'LicenseCompliance|License compliance detected %d license for the source branch only',
              'LicenseCompliance|License compliance detected %d licenses for the source branch only',
              this.licenseReportLength,
            );
      }

      return this.reportContainsDeniedLicense
        ? n__(
            'LicenseCompliance|License compliance detected %d new license and policy violation; approval required',
            'LicenseCompliance|License compliance detected %d new licenses and policy violations; approval required',
            this.licenseReportLength,
          )
        : n__(
            'LicenseCompliance|License compliance detected %d new license',
            'LicenseCompliance|License compliance detected %d new licenses',
            this.licenseReportLength,
          );
    },
    summaryTextWithoutLicenseCheck() {
      if (!this.baseReportHasLicenses) {
        return this.reportContainsDeniedLicense
          ? n__(
              'LicenseCompliance|License compliance detected %d license and policy violation',
              'LicenseCompliance|License compliance detected %d licenses and policy violations',
              this.licenseReportLength,
            )
          : n__(
              'LicenseCompliance|License compliance detected %d license',
              'LicenseCompliance|License compliance detected %d licenses',
              this.licenseReportLength,
            );
      }

      return this.reportContainsDeniedLicense
        ? n__(
            'LicenseCompliance|License compliance detected %d new license and policy violation',
            'LicenseCompliance|License compliance detected %d new licenses and policy violations',
            this.licenseReportLength,
          )
        : n__(
            'LicenseCompliance|License compliance detected %d new license',
            'LicenseCompliance|License compliance detected %d new licenses',
            this.licenseReportLength,
          );
    },
    reportContainsDeniedLicense() {
      return (this.licenseReport || []).some(
        (license) => license.approvalStatus === LICENSE_APPROVAL_STATUS.DENIED,
      );
    },
  },
  actions: {
    setAPISettings(data) {
      this.$patch(data);
    },

    requestManagedLicenses() {
      this.isLoadingManagedLicenses = true;
    },
    receiveManagedLicensesSuccess(licenses = []) {
      this.managedLicenses = licenses.map((license) => normalizeLicense(license)).reverse();
      this.isLoadingManagedLicenses = false;
    },
    receiveManagedLicensesError() {
      this.managedLicenses = [];
      this.isLoadingManagedLicenses = false;
    },
    fetchManagedLicenses() {
      this.requestManagedLicenses();

      const { apiUrlManageLicenses } = this;

      return axios
        .get(apiUrlManageLicenses, { params: { per_page: 100 } })
        .then(({ data }) => {
          this.receiveManagedLicensesSuccess(data);
        })
        .catch(() => {
          this.receiveManagedLicensesError();
        });
    },

    requestParsedLicenseReport() {
      this.isLoadingLicenseReport = true;
    },
    receiveParsedLicenseReportSuccess({ newLicenses, existingLicenses }) {
      this.newLicenses = newLicenses;
      this.existingLicenses = existingLicenses;
      this.isLoadingLicenseReport = false;
      this.loadLicenseReportError = false;
    },
    receiveParsedLicenseReportError(error) {
      this.isLoadingLicenseReport = false;
      this.loadLicenseReportError = error;
    },
    fetchParsedLicenseReport() {
      this.requestParsedLicenseReport();

      pollUntilComplete(this.licensesApiPath)
        .then(({ data }) => {
          const newLicenses = (data.new_licenses || data).map((license) =>
            convertToOldReportFormat(license),
          );
          const existingLicenses = (data.existing_licenses || []).map((license) =>
            convertToOldReportFormat(license),
          );
          this.receiveParsedLicenseReportSuccess({ newLicenses, existingLicenses });
        })
        .catch((error) => {
          this.receiveParsedLicenseReportError(error);
        });
    },
  },
});
