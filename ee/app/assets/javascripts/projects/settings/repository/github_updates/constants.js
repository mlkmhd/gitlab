import { s__ } from '~/locale';

export const POLLING_DELAY = 5000;

// A row can stay pending until the 30-minute repair job, so stop polling a status that no longer changes.
export const POLLING_TIMEOUT = 5 * 60 * 1000;

export const AUTHORITY_STATES = {
  PROVISIONING: 'provisioning',
  PROVIDER_CANONICAL: 'provider_canonical',
  CUTTING_OVER: 'cutting_over',
  CUTOVER_FAILED: 'cutover_failed',
  DISCONNECTED: 'disconnected',
  GITLAB_CANONICAL: 'gitlab_canonical',
};

export const SYNC_STATES = {
  PENDING: 'pending',
  RUNNING: 'running',
  DELAYED: 'delayed',
  CURRENT: 'current',
  DEGRADED: 'degraded',
};

/** Display mapping for the overall authority state; `help` is shown under the status badge. */
export const AUTHORITY_PRESENTATIONS = {
  provisioning: {
    text: s__('GithubUpdatesSettings|Setting up GitHub updates…'),
    variant: 'info',
    help: s__(
      'GithubUpdatesSettings|GitLab is setting up updates from GitHub. This project is read-only.',
    ),
  },
  provider_canonical: {
    text: s__('GithubUpdatesSettings|GitHub updates are on'),
    variant: 'success',
    help: s__(
      'GithubUpdatesSettings|Changes from GitHub are copied to GitLab. This project is read-only while updates are on.',
    ),
  },
  disconnected: {
    text: s__('GithubUpdatesSettings|GitHub connection lost'),
    variant: 'danger',
    help: s__(
      'GithubUpdatesSettings|GitLab must check GitHub for the latest changes before you can make changes in this project.',
    ),
  },
  cutting_over: {
    text: s__('GithubUpdatesSettings|Stopping GitHub updates…'),
    variant: 'info',
    help: s__(
      'GithubUpdatesSettings|GitLab is checking GitHub one last time. This project stays read-only until updates stop.',
    ),
  },
  cutover_failed: {
    text: s__('GithubUpdatesSettings|GitHub updates are still on'),
    variant: 'danger',
    help: s__(
      'GithubUpdatesSettings|GitLab could not complete the final check. This project is still read-only. Try again.',
    ),
  },
  gitlab_canonical: {
    text: s__('GithubUpdatesSettings|Updates stopped'),
    variant: 'neutral',
    help: s__(
      'GithubUpdatesSettings|Updates from GitHub are stopped. To get updates from GitHub again, import the repository again.',
    ),
  },
};

/** Display mapping for the state of one synced data type; `help` explains a state that needs a reader's attention. */
export const SYNC_STATE_PRESENTATIONS = {
  current: { text: s__('GithubUpdatesSettings|Up to date'), variant: 'success' },
  pending: { text: s__('GithubUpdatesSettings|Update scheduled…'), variant: 'neutral' },
  running: { text: s__('GithubUpdatesSettings|Updating…'), variant: 'info' },
  delayed: {
    text: s__('GithubUpdatesSettings|Update delayed'),
    variant: 'warning',
    help: s__(
      "GithubUpdatesSettings|GitHub's rate limit was reached. GitLab tries again when the limit resets.",
    ),
  },
  degraded: {
    text: s__('GithubUpdatesSettings|Error'),
    variant: 'danger',
    help: s__('GithubUpdatesSettings|GitLab could not update this data from GitHub.'),
  },
  paused: {
    text: s__('GithubUpdatesSettings|Paused'),
    variant: 'neutral',
    help: s__(
      'GithubUpdatesSettings|Updates for this data are paused until GitHub updates are active again.',
    ),
  },
  disconnected: {
    text: s__('GithubUpdatesSettings|GitHub connection lost'),
    variant: 'danger',
    help: s__('GithubUpdatesSettings|GitLab no longer has access to this repository.'),
  },
};

/** Shown for every data type once updates have stopped, whatever its stored sync state is. */
export const STOPPED_SYNC_PRESENTATION = {
  text: AUTHORITY_PRESENTATIONS.gitlab_canonical.text,
  variant: AUTHORITY_PRESENTATIONS.gitlab_canonical.variant,
};

export const STOPPABLE_STATES = [
  AUTHORITY_STATES.PROVIDER_CANONICAL,
  AUTHORITY_STATES.CUTOVER_FAILED,
];
