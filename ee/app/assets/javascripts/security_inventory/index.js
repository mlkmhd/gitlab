import { parseBoolean } from '@gitlab/frontend-utils';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import apolloProvider from './graphql/provider';
import App from './components/app.vue';

export default () => {
  const el = document.querySelector('#js-group-security-inventory');
  if (!el) {
    return null;
  }

  const {
    groupFullPath,
    groupId,
    rootGroupName,
    canManageAttributes,
    canReadAttributes,
    canApplyProfiles,
    canReadScanProfiles,
    canAdminRootGroup,
    duoSettingsPath,
    groupOwnersPath,
    groupManageAttributesPath,
    newProjectPath,
  } = el.dataset;

  return initVueApp({
    el,
    apolloProvider,
    provide: {
      groupFullPath,
      groupId,
      rootGroupName,
      canManageAttributes: parseBoolean(canManageAttributes),
      canReadAttributes: parseBoolean(canReadAttributes),
      canApplyProfiles: parseBoolean(canApplyProfiles),
      canReadScanProfiles: parseBoolean(canReadScanProfiles),
      canAdminRootGroup: parseBoolean(canAdminRootGroup),
      duoSettingsPath,
      groupOwnersPath,
      groupManageAttributesPath,
      newProjectPath,
    },
    component: App,
  });
};
