import { parseBoolean } from '@gitlab/frontend-utils';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { convertObjectPropsToCamelCase } from '~/lib/utils/common_utils';
import AiGovernanceSettingsForm from './components/ai_governance_settings_form.vue';

const parseCascadingSettings = (value) => {
  if (!value) return {};

  try {
    return convertObjectPropsToCamelCase(JSON.parse(value), { deep: true });
  } catch {
    return {};
  }
};

export const initAiGovernanceSettings = () => {
  const el = document.getElementById('js-ai-governance-settings');

  if (!el) return null;

  const {
    aiGovernanceEnabled,
    lockAiGovernanceEnabled,
    aiGovernanceCascadingSettings,
    aiAuditEventsStorageEnabled,
    lockAiAuditEventsStorageEnabled,
    aiAuditEventsStorageCascadingSettings,
    updatePath,
  } = el.dataset;

  return initVueApp({
    el,
    name: 'AiGovernanceSettingsRoot',
    component: AiGovernanceSettingsForm,
    provide: {
      aiAuditEventsStorageEnabled: parseBoolean(aiAuditEventsStorageEnabled),
      aiAuditEventsStorageCascadingSettings: parseCascadingSettings(
        aiAuditEventsStorageCascadingSettings,
      ),
    },
    props: {
      initialAiGovernanceEnabled: parseBoolean(aiGovernanceEnabled),
      initialLockAiGovernanceEnabled: parseBoolean(lockAiGovernanceEnabled),
      initialLockAiAuditEventsStorageEnabled: parseBoolean(lockAiAuditEventsStorageEnabled),
      cascadingSettings: parseCascadingSettings(aiGovernanceCascadingSettings),
      updatePath,
    },
  });
};
