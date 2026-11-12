import { ReadableStream } from 'node:stream/web';
import Vue from 'vue';
import { fetch, Request, Response, Headers } from '@whatwg-node/fetch';
import { configure } from '@testing-library/vue';
import { VueRenderer } from '@tiptap/vue-2';
import GlLicensedFeaturesPlugin from '~/vue_shared/gl_licensed_features_plugin';
import GlFeatureFlagsPlugin from '~/vue_shared/gl_feature_flags_plugin';
import GlAbilitiesPlugin from '~/vue_shared/gl_abilities_plugin';
import Translate from '~/vue_shared/translate';
import Executor from '~/glql/core/executor';
import { forgetConsoleCalls, getConsoleCalls, throwErrorFromCalls } from 'helpers/console_watcher';
import {
  clearMissingOperations,
  missingOperations,
  resetCapturedRequests,
} from './core/operation_helpers';
import { CONSOLE_IGNORES } from './console_ignores';
import { server } from './server';
import { setupRouter, setUserSession } from './helpers/setup_utils';
import { resetAllVariants } from './core/fixture_variant_schema';
import { baseMetadata } from './core/constants';
import * as testHelpers from './helpers/test_helpers';

jest.mock('~/actioncable_consumer', () => ({
  __esModule: true,
  default: {
    subscriptions: {
      create: jest.fn(() => ({
        unsubscribe: jest.fn(),
        perform: jest.fn(),
      })),
    },
  },
}));

global.fetch = fetch;
global.Request = Request;
global.Response = Response;
global.Headers = Headers;
global.metadata = baseMetadata;

// tiptap silences its node view prop updates on the root constructor's config. VTU roots the
// app on a local Vue with a cloned config, so that misses the global one Vue's warn() reads.
// Silence the global config for tiptap only, so any other prop mutation still fails.
const { updateProps } = VueRenderer.prototype;
VueRenderer.prototype.updateProps = function updatePropsSilently(...args) {
  const { silent } = Vue.config;
  Vue.config.silent = true;
  try {
    return updateProps.apply(this, args);
  } finally {
    Vue.config.silent = silent;
  }
};

Blob.prototype.stream = function stream() {
  return new ReadableStream({
    start: (controller) => {
      const reader = new FileReader();
      reader.onload = () => {
        controller.enqueue(new Uint8Array(reader.result));
        controller.close();
      };
      reader.onerror = () => controller.error(reader.error);
      reader.readAsArrayBuffer(this);
    },
  });
};

// Mirrors `commons/vue`, which real pages load but neither jest lane does. Without these,
// `glFeatures` injects as `{}` and every flag-gated path takes its "off" branch.
Vue.use(GlLicensedFeaturesPlugin);
Vue.use(GlFeatureFlagsPlugin);
Vue.use(GlAbilitiesPlugin);
Vue.use(Translate);

// Under CI load a starved worker can blow @testing-library's 1000ms waitFor
// default; 3s gives headroom and stays under the suite's testTimeout. Booting the
// app belongs in `waitForSetup`, which has a longer budget, and a test-body wait
// that nears the ceiling is logged by `timedAsyncWrapper`.
configure({ asyncUtilTimeout: 3000, asyncWrapper: testHelpers.timedAsyncWrapper });

let flashContainer;
let consoleThrewImmediately;
let originalConsoleIgnores;

const consoleIgnoresForCurrentFile = () => {
  const { testPath } = expect.getState();

  return Object.values(CONSOLE_IGNORES)
    .filter(({ files }) => files.some((file) => testPath.endsWith(`/${file}`)))
    .map(({ pattern }) => pattern);
};

beforeAll(() => {
  // Record console calls and fail in afterEach. A throw at the call site is often caught by
  // Apollo or app code, so the test would pass.
  consoleThrewImmediately = global.jestConsoleWatcher.shouldThrowImmediately();
  global.jestConsoleWatcher.setShouldThrowImmediately(false);

  originalConsoleIgnores = global.jestConsoleWatcher.getIgnores();
  global.jestConsoleWatcher.setIgnores(
    originalConsoleIgnores.concat(consoleIgnoresForCurrentFile()),
  );

  server.listen({ onUnhandledRequest: 'warn' });
});

beforeEach(async () => {
  // Always set in production (lib/gitlab/gon_helper.rb); REST clients build URLs from it.
  // Set before the awaits below: a previous test's late refetch can run during them.
  window.gon.api_version = 'v4';
  // Always pushed as enabled too (lib/gitlab/gon_helper.rb), so it can't be turned off.
  window.gon.features = { ...window.gon.features, workItemFeaturesField: true };

  // GLQL keeps its clients, result caches and request queues at module level.
  await Promise.all(
    Object.values(Executor.sharedContexts).map(({ client }) => client.clearStore()),
  );
  Executor.sharedContexts = {};
  Executor.taskQueues = {};

  // MSW 2 streams response bodies across event-loop ticks. When a test finishes
  // mid-stream, the response arrives in the next test's fresh cache. cache.reset()
  // does not cancel in-flight requests, so Apollo's deduplication reuses the stale
  // response. clearMountedApolloStores() cancels these fetches. We do this in
  // beforeEach so the previous test's components are already destroyed.
  await testHelpers.clearMountedApolloStores();
  // Drop anything the previous test's cancelled requests logged after its afterEach.
  forgetConsoleCalls();

  const { router } = global.metadata;
  if (router) {
    await setupRouter(router);
  }
  // Do not reset `gon.features` / `gon.licensed_features` here: `shared_test_setup.js`
  // rebuilds `window.gon` before every test, so `setFeatureFlags` and
  // `setLicensedFeatures` already start from a clean base.
  // We default to logged in user for test. In scenarios where
  // we want logged out, consumers can call `setUserSession(false)`
  // in a describe block.
  setUserSession(true);

  // createAlert is a no-op without this container, which the page layout provides.
  flashContainer = document.createElement('div');
  flashContainer.className = 'flash-container';
  document.body.appendChild(flashContainer);
});

afterEach(() => {
  // The rest of the reset runs in `finally`, so a failing teardown cannot leak the
  // handlers, fixture variants and session into every later test in the file.
  try {
    testHelpers.unmountBootstrappedApps();

    const consoleCalls = getConsoleCalls();
    if (consoleCalls.length) {
      throwErrorFromCalls(consoleCalls);
    }
  } finally {
    forgetConsoleCalls();
    flashContainer?.remove();
    flashContainer = null;
    server.resetHandlers();
    global.metadata = baseMetadata;
    resetCapturedRequests();
    resetAllVariants();
    localStorage.clear();
    setUserSession(true);
  }
});

afterAll(() => {
  // `server.close()` must run even if the missing-handler check throws. Otherwise the
  // MSW server leaks, the worker never exits, and Jest hangs until --forceExit masks the run.
  try {
    global.jestConsoleWatcher.setShouldThrowImmediately(consoleThrewImmediately);
    global.jestConsoleWatcher.setIgnores(originalConsoleIgnores);

    if (missingOperations.size > 0) {
      const operations = Array.from(missingOperations, (el) => `\n - ${el}`);
      clearMissingOperations();
      throw new Error(
        `Test suite is missing graphql handlers for operations: ${operations}\n\nSee https://docs.gitlab.com/ee/development/testing_guide/frontend_testing/#write-feature-handlers`,
      );
    }
  } finally {
    server.close();
  }
});
