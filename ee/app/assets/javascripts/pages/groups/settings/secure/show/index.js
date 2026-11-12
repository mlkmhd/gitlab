import initSettingsPanels from '~/settings_panels';
import { initSettingsToggles } from '~/group_settings/settings_toggles';
import { initGroupSecretsManagerSettings } from 'ee/groups/settings/permissions';
import { initAiGovernanceSettings } from 'ee/ai/settings/init_ai_governance_settings';

initSettingsPanels();
initSettingsToggles();
initGroupSecretsManagerSettings();
initAiGovernanceSettings();
