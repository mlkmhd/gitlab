import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { pinia } from '~/pinia/instance';

import { createAlert } from '~/alert';
import { s__ } from '~/locale';
import StatusChecks from './components/status_checks.vue';
import { useStatusChecks } from './store';

export default function mountProjectSettingsApprovals(el) {
  if (!el) {
    return null;
  }

  const store = useStatusChecks(pinia);
  const { projectId, statusChecksPath } = el.dataset;

  store.setSettings({ projectId, statusChecksPath });
  store.fetchStatusChecks().catch((error) => {
    createAlert({
      message: s__('StatusCheck|An error occurred fetching the status checks.'),
      captureError: true,
      error,
    });
  });

  return initVueApp({ el, name: 'StatusChecksRoot', pinia, component: StatusChecks });
}
