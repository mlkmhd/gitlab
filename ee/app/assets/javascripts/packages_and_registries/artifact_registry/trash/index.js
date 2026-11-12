import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import App from './app.vue';

export const initArtifactRegistryTrash = () => {
  const el = document.getElementById('js-artifact-registry-trash');

  if (!el) return false;

  return initVueApp({
    el,
    name: 'ArtifactRegistryTrashRoot',
    component: App,
  });
};
