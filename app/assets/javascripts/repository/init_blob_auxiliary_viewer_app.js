import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import apolloProvider from '~/repository/graphql';
import BlobAuxiliaryViewer from '~/repository/components/blob_auxiliary_viewer.vue';
import repositoryPathMixin from '~/repository/mixins/repository_path';

const mountApp = (el, router, { projectPath, ref }) =>
  initVueApp({
    el,
    name: 'BlobAuxiliaryViewerRoot',
    router,
    apolloProvider,
    component: {
      name: 'BlobAuxiliaryViewerApp',
      mixins: [repositoryPathMixin],
      computed: {
        isBlobRoute() {
          return Boolean(this.$route.name?.startsWith('blobPath'));
        },
        refType() {
          return this.$route.meta.refType || this.$route.query.ref_type;
        },
      },
      render(h) {
        if (!this.isBlobRoute) return null;

        return h(BlobAuxiliaryViewer, {
          key: this.computedPath,
          props: {
            path: this.computedPath,
            projectPath,
            currentRef: ref,
            refType: this.refType,
          },
        });
      },
    },
  });

// The server renders the auxiliary viewer for the first page, so mounting
// (which replaces it) waits for the first client-side navigation.
export default function initBlobAuxiliaryViewerApp(router, { projectPath, ref }) {
  const el = document.getElementById('js-blob-auxiliary-viewer');
  if (!el) return null;

  return new Promise((resolve) => {
    const removeHook = router.afterEach((to, from) => {
      if (!from.name || to.path === from.path) return;

      removeHook();
      resolve(mountApp(el, router, { projectPath, ref }));
    });
  });
}
