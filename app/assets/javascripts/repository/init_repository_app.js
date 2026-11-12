import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import createStore from '~/code_navigation/store';
import { pinia } from '~/pinia/instance';
import apolloProvider from './graphql';
import RepositoryApp from './components/app.vue';
import createRouter from './router';
import { initClientQueries } from './utils/init_client_queries';
import { parseRepositoryAppDataset } from './utils/parse_repository_app_dataset';
import { createHighlightWorker } from './utils/highlight_worker_utils';

// Mounts the single repository layout root on `#js-repository-app`, returning
// the same shape as `initRepositoryPage()` for the EE wrappers.
export default function initRepositoryApp(el) {
  const { dataset } = el;
  const { projectPath, projectShortPath, fullName, ref, escapedRef, props, provide } =
    parseRepositoryAppDataset(dataset);

  // The route patterns embed encoded variants of the base ref, so the base
  // must be the pre-encoded ref; a raw ref containing '#' or '%' double-encodes.
  const router = createRouter(projectPath, escapedRef, fullName);

  initClientQueries({ projectPath, projectShortPath, ref, escapedRef });

  initVueApp({
    el,
    name: 'RepositoryAppRoot',
    store: createStore(),
    pinia,
    router,
    apolloProvider,
    provide: { ...provide, highlightWorker: createHighlightWorker() },
    component: RepositoryApp,
    props,
  });

  return { router, data: dataset, apolloProvider, projectPath };
}
