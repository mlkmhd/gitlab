import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { pinia } from '~/pinia/instance';
import DeployFreezeSettings from './components/deploy_freeze_settings.vue';
import { useDeployFreeze } from './store';

export default () => {
  const el = document.getElementById('js-deploy-freeze-table');

  if (!el) {
    return null;
  }

  const { projectId, timezoneData } = el.dataset;

  useDeployFreeze(pinia).setInitialState({
    projectId,
    timezoneData: JSON.parse(timezoneData),
  });

  return initVueApp({
    el,
    name: 'DeployFreezeSettingsRoot',
    pinia,
    component: DeployFreezeSettings,
  });
};
