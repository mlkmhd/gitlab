import initOrbitSettings from 'ee/orbit/init_settings';
import { registerBootstrappedApp, screen, within } from 'ee_jest/integration/helpers/test_helpers';
import groupSettings from 'test_fixtures/graphql/orbit/integration/get_orbit_group_settings.query.graphql.json';
import { resetOrbitState } from './handlers';

export const ORBIT_PATH = '/dashboard/orbit';

export function mountGroupSettings() {
  resetOrbitState();

  const el = document.createElement('div');
  el.id = 'js-orbit-settings';
  Object.assign(el.dataset, {
    groupFullPath: groupSettings.data.group.fullPath,
    orbitPlatform: JSON.stringify({ saas: true, instance: null }),
    duoAvailable: 'true',
    orbitPath: ORBIT_PATH,
    usageQuotasPath: '/groups/orbit-fixtures/-/usage_quotas',
    duoSettingsPath: '/groups/orbit-fixtures/-/settings/gitlab_duo',
  });
  document.body.appendChild(el);

  return registerBootstrappedApp(initOrbitSettings());
}

export const findToggle = () => {
  const toggle = screen.queryByTestId('orbit-toggle');
  return toggle && within(toggle).queryByRole('switch');
};
export const findStatusAlert = () => screen.queryByTestId('orbit-status-alert');
export const findActionError = () => screen.queryByTestId('orbit-action-error');
export const findTrialEndedAlert = () => screen.queryByTestId('orbit-trial-ended-alert');
export const findSettingsPage = () => screen.queryByTestId('orbit-group-settings');
export const findTurnOnConfirmButton = () => {
  const modal = document.getElementById('orbit-turn-on-confirm-modal');
  return modal?.closest('.modal')?.classList.contains('show')
    ? within(modal).queryByRole('button', { name: 'Turn on GitLab Orbit' })
    : null;
};
