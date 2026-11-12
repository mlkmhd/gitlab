import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { pinia } from '~/pinia/instance';
import BadgeSettings from '~/badges/components/badge_settings.vue';
import { useBadgeSettings } from '~/badges/store';

export default (kind) => {
  const badgeSettingsElement = document.getElementById('badge-settings');

  if (!badgeSettingsElement) return null;

  useBadgeSettings(pinia).setInitialState({
    kind,
    apiEndpointUrl: badgeSettingsElement.dataset.apiEndpointUrl,
  });

  return initVueApp({
    el: badgeSettingsElement,
    name: 'BadgeSettingsRoot',
    pinia,
    component: BadgeSettings,
  });
};
