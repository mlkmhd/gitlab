import { s__ } from '~/locale';
import {
  AUTHORITY_STATES,
  STOPPED_SYNC_PRESENTATION,
  SYNC_STATE_PRESENTATIONS,
  SYNC_STATES,
} from './constants';

// The backend's `inventory` domain is deliberately not shown.
// Update now does not run LFS (the source pass requests it), so its row never affects that button.
const DATA_ROWS = [
  { key: 'source', label: s__('GithubUpdatesSettings|Repository') },
  { key: 'work_items', label: s__('GithubUpdatesSettings|Issues and merge requests') },
  { key: 'lfs', label: s__('GithubUpdatesSettings|LFS objects'), updatedByUpdateNow: false },
];

/**
 * Builds the fixed table rows from the `data` of a status response.
 *
 * A row whose state is missing or unknown is `unavailable` rather than showing the backend's value.
 * Once updates have stopped the stored states no longer describe anything, so every row shows that instead.
 */
export function buildDataRows(statusData, authorityState) {
  return DATA_ROWS.map(({ key, label, updatedByUpdateNow = true }) => {
    const {
      state,
      last_updated_at: lastUpdatedAt,
      last_checked_at: lastCheckedAt,
    } = statusData[key] || {};
    const presentation =
      authorityState === AUTHORITY_STATES.GITLAB_CANONICAL
        ? STOPPED_SYNC_PRESENTATION
        : SYNC_STATE_PRESENTATIONS[state];

    return {
      key,
      label,
      // An error is included so Update now can retry it.
      isUpdatable:
        !updatedByUpdateNow || [SYNC_STATES.CURRENT, SYNC_STATES.DEGRADED].includes(state),
      statusText: presentation?.text || s__('GithubUpdatesSettings|Status unavailable'),
      statusVariant: presentation?.variant || 'neutral',
      statusHelp: presentation?.help || '',
      lastUpdatedAt: lastUpdatedAt || null,
      lastCheckedAt: lastCheckedAt || null,
    };
  });
}

// A disconnected project keeps its rows' last states, but nothing runs until a reconnect, which reloads the page.
const SETTLED_AUTHORITY_STATES = [AUTHORITY_STATES.GITLAB_CANONICAL, AUTHORITY_STATES.DISCONNECTED];
const IN_PROGRESS_AUTHORITY_STATES = [AUTHORITY_STATES.PROVISIONING, AUTHORITY_STATES.CUTTING_OVER];
// A delayed row runs again by itself once GitHub's rate limit resets.
const IN_PROGRESS_SYNC_STATES = [SYNC_STATES.PENDING, SYNC_STATES.RUNNING, SYNC_STATES.DELAYED];

/** Whether the status is still expected to change on its own, for example while an update or a stop runs. */
export function isStatusInProgress({ state, data }) {
  if (SETTLED_AUTHORITY_STATES.includes(state)) return false;
  if (IN_PROGRESS_AUTHORITY_STATES.includes(state)) return true;

  return DATA_ROWS.some(({ key }) => IN_PROGRESS_SYNC_STATES.includes(data?.[key]?.state));
}
