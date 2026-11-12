import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import GithubUpdatesApp from './github_updates_app.vue';

export default function mountGithubUpdates() {
  const el = document.getElementById('js-github-updates-settings');

  if (!el) {
    return null;
  }

  const {
    statusUrl,
    updateNowUrl,
    stopUrl,
    projectFullPath,
    repositoryName,
    repositoryUrl,
    initialStatus,
  } = el.dataset;

  return initVueApp({
    el,
    name: 'GithubUpdatesSettingsRoot',
    component: GithubUpdatesApp,
    props: {
      statusUrl,
      updateNowUrl,
      stopUrl,
      projectFullPath,
      repositoryName,
      repositoryUrl,
      initialStatus: JSON.parse(initialStatus),
    },
  });
}
