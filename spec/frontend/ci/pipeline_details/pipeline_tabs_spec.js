import PipelineTabs from 'ee_else_ce/ci/pipeline_details/tabs/pipeline_tabs.vue';
import { createAppOptions, createPipelineTabs } from '~/ci/pipeline_details/pipeline_tabs';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { pinia } from '~/pinia/instance';
import { useTestReportsStore } from '~/ci/pipeline_details/stores/test_reports';

jest.mock('~/lib/utils/vue3compat/init_vue_app', () => ({
  initVueApp: jest.fn().mockReturnValue('root instance'),
}));

jest.mock('~/lib/utils/url_utility', () => ({
  removeParams: () => 'gitlab.com',
  joinPaths: () => {},
  setUrlFragment: () => {},
}));

jest.mock('~/ci/pipeline_details/utils', () => ({
  getPipelineDefaultTab: () => '',
}));

describe('~/ci/pipeline_details/pipeline_tabs.js', () => {
  describe('createAppOptions', () => {
    const SELECTOR = 'SELECTOR';

    let el;

    const createElement = () => {
      el = document.createElement('div');
      el.id = SELECTOR;
      el.dataset.canGenerateCodequalityReports = 'true';
      el.dataset.codequalityReportDownloadPath = 'codequalityReportDownloadPath';
      el.dataset.exposeSecurityDashboard = 'true';
      el.dataset.exposeLicenseScanningData = 'true';
      el.dataset.failedJobsCount = 1;
      el.dataset.graphqlResourceEtag = 'graphqlResourceEtag';
      el.dataset.pipelineIid = '123';
      el.dataset.pipelineProjectPath = 'pipelineProjectPath';
      el.dataset.blobPath = 'blobPath';
      el.dataset.summaryEndpoint = 'summaryEndpoint';
      el.dataset.suiteEndpoint = 'suiteEndpoint';

      document.body.appendChild(el);
    };

    afterEach(() => {
      el = null;
    });

    it("extracts the properties from the element's dataset", () => {
      createElement();
      const options = createAppOptions(`#${SELECTOR}`, null);

      expect(options.el).toEqual(el);
      expect(options.provide).toMatchObject({
        canGenerateCodequalityReports: true,
        codequalityReportDownloadPath: 'codequalityReportDownloadPath',
        exposeSecurityDashboard: true,
        exposeLicenseScanningData: true,
        failedJobsCount: '1',
        graphqlResourceEtag: 'graphqlResourceEtag',
        pipelineIid: '123',
        pipelineProjectPath: 'pipelineProjectPath',
      });
    });

    it('mounts PipelineTabs as the root component', () => {
      createElement();
      const options = createAppOptions(`#${SELECTOR}`, null);

      expect(options.component).toBe(PipelineTabs);
    });

    it('seeds the test reports store and passes the shared Pinia instance', () => {
      createElement();
      const options = createAppOptions(`#${SELECTOR}`, null);
      const store = useTestReportsStore(pinia);

      expect(options.pinia).toBe(pinia);
      expect(store.blobPath).toBe('blobPath');
      expect(store.summaryEndpoint).toBe('summaryEndpoint');
      expect(store.suiteEndpoint).toBe('suiteEndpoint');
    });

    it('returns `null` if el does not exist', () => {
      expect(createAppOptions('foo', null)).toBe(null);
    });
  });

  describe('createPipelineTabs', () => {
    it('mounts the app options with initVueApp and returns the root instance', () => {
      const options = { el: '#app' };

      expect(createPipelineTabs(options)).toBe('root instance');
      expect(initVueApp).toHaveBeenCalledWith(options);
    });

    it('does not mount anything without options', () => {
      expect(createPipelineTabs(null)).toBe(null);
      expect(initVueApp).not.toHaveBeenCalled();
    });
  });
});
