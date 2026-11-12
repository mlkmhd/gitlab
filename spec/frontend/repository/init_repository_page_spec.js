import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import HighlightWorker from '~/highlight_js/workers/highlight_worker?worker';
import initRepositoryPage from '~/repository/init_repository_page';
import initFileTreeBrowser from '~/repository/file_tree_browser';
import initHeaderApp from '~/repository/init_header_app';
import initLastCommitApp from '~/repository/init_last_commit_app';
import initForkInfoApp from '~/repository/init_fork_info_app';
import initRepositoryApp from '~/repository/init_repository_app';
import createRouter from '~/repository/router';
import apolloProvider from '~/repository/graphql';
import LegacyRepositoryApp from '~/repository/components/legacy_app.vue';
import { initClientQueries } from '~/repository/utils/init_client_queries';

// Explicit factories: automocks would evaluate the real modules, several of
// which import `~/lib/graphql`, which cannot be evaluated twice (it defines
// window.pendingApolloRequests).
jest.mock('~/lib/utils/vue3compat/init_vue_app');
jest.mock('~/repository/utils/init_client_queries', () => ({ initClientQueries: jest.fn() }));
jest.mock('~/repository/file_tree_browser', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('~/repository/init_header_app', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('~/repository/init_last_commit_app', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('~/repository/init_fork_info_app', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('~/repository/init_repository_app', () => ({ __esModule: true, default: jest.fn() }));
jest.mock('~/highlight_js/workers/highlight_worker?worker', () => ({
  __esModule: true,
  default: jest.fn(),
}));
// A stub router is enough: mounting is mocked, so the router is only passed
// around, and requiring the real one would double-load `~/lib/graphql`.
jest.mock('~/repository/router', () => ({
  __esModule: true,
  default: jest.fn(() => ({ name: 'mockRouter' })),
}));

const PROJECT_PATH = 'group/project';
const PROJECT_SHORT_PATH = 'project';
const FULL_NAME = 'Group / Project';
// A ref with special characters is the case the base-ref choice exists for.
const RAW_REF = 'feature/#123';
const ESCAPED_REF = 'feature/%23123';

describe('initRepositoryPage', () => {
  const setTreeHTML = () => {
    document.body.innerHTML = `
      <div id="js-tree-list"
        data-project-path="${PROJECT_PATH}"
        data-project-short-path="${PROJECT_SHORT_PATH}"
        data-ref="${RAW_REF}"
        data-escaped-ref="${ESCAPED_REF}"
        data-full-name="${FULL_NAME}"
        data-ref-type="heads"
        data-resource-id="gid://gitlab/Project/1"
        data-explain-code-available="false"
        data-has-revs-file="true"></div>`;
  };

  const setBlobHTML = () => {
    document.body.innerHTML = `
      <div id="js-view-blob-app"
        data-blob-path="lib/utils.js"
        data-project-path="${PROJECT_PATH}"
        data-original-branch="${RAW_REF}"
        data-escaped-ref="${ESCAPED_REF}"
        data-full-name="${FULL_NAME}"
        data-ref-type="heads"
        data-can-download-code="true"></div>
      <div id="js-repository-blob-header-app"
        data-project-short-path="${PROJECT_SHORT_PATH}"></div>`;
  };

  const setRepositoryAppHTML = () => {
    document.body.innerHTML = `
      <div id="js-repository-app"></div>
      <div id="js-tree-list"></div>`;
  };

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('returns null and mounts nothing without a mount point', () => {
    expect(initRepositoryPage()).toBe(null);
    expect(initVueApp).not.toHaveBeenCalled();
  });

  describe.each`
    page      | setHTML        | mountId
    ${'tree'} | ${setTreeHTML} | ${'js-tree-list'}
    ${'blob'} | ${setBlobHTML} | ${'js-view-blob-app'}
  `('on the $page page', ({ setHTML, mountId }) => {
    let result;

    beforeEach(() => {
      setHTML();
      result = initRepositoryPage();
    });

    it('creates the router once with the pre-encoded ref as base', () => {
      expect(createRouter).toHaveBeenCalledTimes(1);
      expect(createRouter).toHaveBeenCalledWith(PROJECT_PATH, ESCAPED_REF, FULL_NAME);
    });

    it('seeds the client queries with the raw and escaped refs', () => {
      expect(initClientQueries).toHaveBeenCalledWith({
        projectPath: PROJECT_PATH,
        projectShortPath: PROJECT_SHORT_PATH,
        ref: RAW_REF,
        escapedRef: ESCAPED_REF,
      });
    });

    it('initializes the shared repository roots with the shared router', () => {
      const router = createRouter.mock.results[0].value;

      expect(initFileTreeBrowser).toHaveBeenCalledWith(router, {
        projectPath: PROJECT_PATH,
        ref: RAW_REF,
        refType: 'heads',
      });
      expect(initHeaderApp).toHaveBeenCalledWith({ router });
      expect(initLastCommitApp).toHaveBeenCalledWith(router);
      expect(initForkInfoApp).toHaveBeenCalled();
    });

    it('mounts LegacyRepositoryApp on the page mount point providing the raw ref', () => {
      expect(initVueApp).toHaveBeenCalledWith(
        expect.objectContaining({
          el: document.getElementById(mountId),
          component: LegacyRepositoryApp,
          router: createRouter.mock.results[0].value,
          apolloProvider,
          provide: expect.objectContaining({
            originalBranch: RAW_REF,
            hasRevsFile: expect.any(Boolean),
          }),
        }),
      );
    });

    it('returns the shared router and Apollo provider for EE extensions', () => {
      expect(result).toMatchObject({ projectPath: PROJECT_PATH });
      expect(result.router).toBe(createRouter.mock.results[0].value);
      expect(result.apolloProvider).toBe(apolloProvider);
    });
  });

  describe('highlight worker', () => {
    const providedWorker = () => initVueApp.mock.calls[0][0].provide.highlightWorker;

    beforeEach(() => {
      setTreeHTML();
    });

    it('provides a highlight worker instance', () => {
      initRepositoryPage();

      expect(providedWorker()).toBe(HighlightWorker.mock.instances[0]);
    });

    it('mounts the app with a null worker when the browser refuses to construct it', () => {
      HighlightWorker.mockImplementationOnce(() => {
        throw new Error("SecurityError: Failed to construct 'Worker'");
      });

      expect(() => initRepositoryPage()).not.toThrow();
      expect(initVueApp).toHaveBeenCalledTimes(1);
      expect(providedWorker()).toBe(null);
    });
  });

  describe('with the single repository app mount point', () => {
    const repositoryApp = { router: { name: 'mockRouter' } };
    let result;

    beforeEach(() => {
      initRepositoryApp.mockReturnValue(repositoryApp);
      setRepositoryAppHTML();
      result = initRepositoryPage();
    });

    it('delegates to initRepositoryApp and returns its result', () => {
      expect(initRepositoryApp).toHaveBeenCalledTimes(1);
      expect(initRepositoryApp).toHaveBeenCalledWith(document.getElementById('js-repository-app'));
      expect(result).toBe(repositoryApp);
    });

    it('does not initialize the legacy repository roots', () => {
      expect(initFileTreeBrowser).not.toHaveBeenCalled();
      expect(initHeaderApp).not.toHaveBeenCalled();
      expect(initLastCommitApp).not.toHaveBeenCalled();
      expect(initForkInfoApp).not.toHaveBeenCalled();
      expect(initVueApp).not.toHaveBeenCalled();
    });
  });
});
