import initBlobShow from '~/blob/show/show_blob_bundle';
import { BlobViewer, initAuxiliaryViewer } from '~/blob/viewer/index';
import initBlob from '~/pages/projects/init_blob';
import initRepositoryPage from '~/repository/init_repository_page';
import initForkInfoApp from '~/repository/init_fork_info_app';

// Explicit factories: the real modules mount apps and import `~/lib/graphql`,
// which cannot be evaluated twice.
jest.mock('~/blob/viewer/index', () => ({ BlobViewer: jest.fn(), initAuxiliaryViewer: jest.fn() }));
jest.mock('~/pages/projects/init_blob', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('~/pages/projects/shared/web_ide_link/init_web_ide_link', () => ({
  initWebIdeLink: jest.fn(),
}));
jest.mock('~/sourcegraph/load', () => ({}));
jest.mock('~/vue_shared/components/ref/init_ambiguous_ref_modal', () => ({
  __esModule: true,
  default: jest.fn(),
}));
jest.mock('~/repository/init_repository_page', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('~/repository/graphql', () => ({ __esModule: true, default: {} }));
jest.mock('~/lib/utils/local_storage_alert', () => ({ showAlertFromLocalStorage: jest.fn() }));
jest.mock('~/repository/init_fork_info_app', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('~/performance/init_performance_plugin', () => ({
  __esModule: true,
  default: jest.fn(),
}));

describe('initBlobShow', () => {
  const router = { name: 'mockRouter' };

  beforeEach(() => {
    initRepositoryPage.mockReturnValue({ router });
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  describe.each`
    mountId                | auxiliaryViewerCalls
    ${'js-repository-app'} | ${0}
    ${'js-view-blob-app'}  | ${1}
  `('with #$mountId', ({ mountId, auxiliaryViewerCalls }) => {
    let result;

    beforeEach(() => {
      document.body.innerHTML = `<div id="${mountId}"></div>`;
      result = initBlobShow();
    });

    it('initializes the repository page and returns its router', () => {
      expect(initRepositoryPage).toHaveBeenCalledTimes(1);
      expect(initBlob).toHaveBeenCalledTimes(1);
      expect(result.router).toBe(router);
    });

    it('does not fall back to the legacy blob viewer', () => {
      expect(BlobViewer).not.toHaveBeenCalled();
      expect(initForkInfoApp).not.toHaveBeenCalled();
    });

    it(`initializes the auxiliary viewer ${auxiliaryViewerCalls} time(s)`, () => {
      expect(initAuxiliaryViewer).toHaveBeenCalledTimes(auxiliaryViewerCalls);
    });
  });

  describe('without a repository mount point', () => {
    let result;

    beforeEach(() => {
      result = initBlobShow();
    });

    it('falls back to the legacy blob viewer without a router', () => {
      expect(initRepositoryPage).not.toHaveBeenCalled();
      expect(BlobViewer).toHaveBeenCalledTimes(1);
      expect(initForkInfoApp).toHaveBeenCalledTimes(1);
      expect(result.router).toBe(null);
    });
  });
});
