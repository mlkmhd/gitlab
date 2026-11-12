import Vue from 'vue';
import VueRouter from 'vue-router';
import VueApollo from 'vue-apollo';
import { parseBoolean } from '@gitlab/frontend-utils';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import PipelineTabs from 'ee_else_ce/ci/pipeline_details/tabs/pipeline_tabs.vue';
import { pinia } from '~/pinia/instance';
import { useTestReportsStore } from './stores/test_reports';
import { getPipelineDefaultTab } from './utils';

Vue.use(VueApollo);
Vue.use(VueRouter);

export const createAppOptions = (selector, apolloProvider, router) => {
  const el = document.querySelector(selector);

  if (!el) return null;

  const { dataset } = el;
  const {
    canGenerateCodequalityReports,
    codequalityReportDownloadPath,
    exposeSecurityDashboard,
    exposeLicenseScanningData,
    failedJobsCount,
    projectPath,
    graphqlResourceEtag,
    pipelineIid,
    pipelineProjectPath,
    totalJobCount,
    licenseManagementApiUrl,
    licenseScanCount,
    licensesApiPath,
    canManageLicenses,
    summaryEndpoint,
    suiteEndpoint,
    blobPath,
    hasTestReport,
    isFullCodequalityReportAvailable,
    securityPoliciesPath,
    testsCount,
    manualVariablesCount,
    manualVariablesFileMissing,
    canReadVariables,
    displayPipelineVariables,
  } = dataset;

  const defaultTabValue = getPipelineDefaultTab(window.location.href);

  useTestReportsStore(pinia).setInitialState({ blobPath, summaryEndpoint, suiteEndpoint });

  return {
    el,
    name: 'PipelineDetailsRoot',
    component: PipelineTabs,
    apolloProvider,
    pinia,
    router,
    provide: {
      canGenerateCodequalityReports: parseBoolean(canGenerateCodequalityReports),
      codequalityReportDownloadPath,
      isFullCodequalityReportAvailable: parseBoolean(isFullCodequalityReportAvailable),
      projectPath,
      defaultTabValue,
      exposeSecurityDashboard: parseBoolean(exposeSecurityDashboard),
      exposeLicenseScanningData: parseBoolean(exposeLicenseScanningData),
      failedJobsCount,
      graphqlResourceEtag,
      pipelineIid,
      pipelineProjectPath,
      totalJobCount,
      licenseManagementApiUrl,
      licenseScanCount,
      licensesApiPath,
      canManageLicenses: parseBoolean(canManageLicenses),
      blobPath,
      hasTestReport,
      securityPoliciesPath,
      testsCount,
      manualVariablesCount: Number.parseInt(manualVariablesCount, 10),
      manualVariablesFileMissing: parseBoolean(manualVariablesFileMissing),
      canReadVariables: parseBoolean(canReadVariables),
      displayPipelineVariables: parseBoolean(displayPipelineVariables),
    },
  };
};

export const createPipelineTabs = (options) => {
  if (!options) return null;

  return initVueApp(options);
};
