import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import HighlightWorker from '~/highlight_js/workers/highlight_worker?worker';
import initRepositoryApp from '~/repository/init_repository_app';
import createRouter from '~/repository/router';
import apolloProvider from '~/repository/graphql';
import RepositoryApp from '~/repository/components/app.vue';
import { initClientQueries } from '~/repository/utils/init_client_queries';

jest.mock('~/lib/utils/vue3compat/init_vue_app');
jest.mock('~/repository/utils/init_client_queries', () => ({ initClientQueries: jest.fn() }));
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

describe('initRepositoryApp', () => {
  let el;
  let result;

  beforeEach(() => {
    document.body.innerHTML = `
      <div id="js-repository-app"
        data-project-id="1"
        data-project-path="${PROJECT_PATH}"
        data-project-short-path="${PROJECT_SHORT_PATH}"
        data-ref="${RAW_REF}"
        data-escaped-ref="${ESCAPED_REF}"
        data-full-name="${FULL_NAME}"
        data-ref-type="heads"
        data-suggested-target-branch="user-patch-1"
        data-history-link="/${PROJECT_PATH}/-/commits/main"
        data-has-revs-file="true"></div>`;
    el = document.getElementById('js-repository-app');
    result = initRepositoryApp(el);
  });

  afterEach(() => {
    document.body.innerHTML = '';
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

  it('mounts RepositoryApp with the parsed props and provide', () => {
    expect(initVueApp).toHaveBeenCalledTimes(1);
    expect(initVueApp).toHaveBeenCalledWith(
      expect.objectContaining({
        el,
        component: RepositoryApp,
        router: createRouter.mock.results[0].value,
        apolloProvider,
        props: expect.objectContaining({
          projectPath: PROJECT_PATH,
          projectId: '1',
          currentRef: RAW_REF,
          refType: 'heads',
        }),
        provide: expect.objectContaining({
          originalBranch: RAW_REF,
          selectedBranch: 'user-patch-1',
          hasRevsFile: true,
          highlightWorker: HighlightWorker.mock.instances[0],
        }),
      }),
    );
  });

  it('returns the same shape as the legacy path', () => {
    expect(result).toMatchObject({ projectPath: PROJECT_PATH });
    expect(result.router).toBe(createRouter.mock.results[0].value);
    expect(result.apolloProvider).toBe(apolloProvider);
    expect(result.data).toBe(el.dataset);
  });
});
