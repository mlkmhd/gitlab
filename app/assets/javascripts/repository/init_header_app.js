import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { pinia } from '~/pinia/instance';
import apolloProvider from './graphql';
import HeaderArea from './components/header_area.vue';
import createRouter from './router';
import { initClientQueries } from './utils/init_client_queries';
import { parseHeaderAreaProvide } from './utils/parse_header_area_dataset';

export default function initHeaderApp({ router, isReadmeView = false }) {
  const headerEl = document.getElementById('js-repository-blob-header-app');
  if (headerEl) {
    const { dataset } = headerEl;
    const { ref, escapedRef, refType, projectId, projectPath, projectShortPath, fullName } =
      dataset;

    // Repository pages seed these once through initRepositoryPage(); a
    // standalone header mount (readme view) owns its own seeding.
    if (!router) initClientQueries({ projectPath, projectShortPath, ref, escapedRef });

    initVueApp({
      el: headerEl,
      name: 'RepositoryHeaderAreaRoot',
      pinia,
      provide: parseHeaderAreaProvide(dataset, {
        selectedBranch: dataset.breadcrumbsSelectedBranch,
        isReadmeView,
      }),
      apolloProvider,
      router: router || createRouter(projectPath, escapedRef, fullName),
      component: HeaderArea,
      props: {
        refType,
        currentRef: ref,
        projectPath,
        projectId,
      },
    });
  }
}
