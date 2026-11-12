import { __, s__ } from '~/locale';

// Strings of the GitLab Duo section that are looked up by a state or key from the backend, or shared by
// several of its components. Strings used in one place are inline.

export const BADGES = {
  on: __('On'),
  off: __('Off'),
  elsewhere: s__('SlackIntegration|Managed in another group'),
  admin: s__('SlackIntegration|Managed by your administrator'),
  needsAttention: __('Needs attention'),
};

// What the page says about a workspace whose GitLab Duo the viewer can't change here. Keys are row states
// or notice keys from the backend; `_unnamed` variants apply when the viewer can't see the group.
export const NOTICES = {
  personal_namespace: s__(
    "SlackIntegration|GitLab Duo can't run in a personal namespace. To use GitLab Duo in Slack, install the GitLab for Slack app on a top-level group.",
  ),
  not_connected: s__(
    'SlackIntegration|Install the GitLab for Slack app to use GitLab Duo in Slack.',
  ),
  instance_managed_on: s__(
    'SlackIntegration|%{workspace} is connected for the whole instance. Your administrator decides where GitLab Duo runs for it: %{group}.',
  ),
  // GitLab Duo is on in a group the viewer can't see.
  instance_managed_on_unnamed: s__(
    'SlackIntegration|%{workspace} is connected for the whole instance. Your administrator decides where GitLab Duo runs for it.',
  ),
  instance_managed_off: s__(
    "SlackIntegration|%{workspace} is connected for the whole instance. Your administrator decides where GitLab Duo runs for it, and hasn't chosen a group yet, so it's off.",
  ),
  off_ask_owner: s__(
    'SlackIntegration|GitLab Duo is off for %{workspace}. An Owner of %{group} can turn it on.',
  ),
  off_ask_owner_unnamed: s__(
    'SlackIntegration|GitLab Duo is off for %{workspace}. An Owner of the top-level group can turn it on.',
  ),
  off_install_on_top_level: s__(
    'SlackIntegration|GitLab Duo in Slack is turned on by installing the GitLab for Slack app on the top-level group. Ask an Owner of %{group} to install it for %{workspace}.',
  ),
  off_install_on_top_level_unnamed: s__(
    'SlackIntegration|GitLab Duo in Slack is turned on by installing the GitLab for Slack app on the top-level group. Ask an Owner of the top-level group to install it for %{workspace}.',
  ),
  off_by_owners: s__(
    'SlackIntegration|GitLab Duo is off for %{workspace}. An Owner of this group can turn it on.',
  ),
  on_here_read_only: s__(
    'SlackIntegration|%{workspace} runs GitLab Duo in %{group}. Members of %{group} with at least the Developer role can use it. An Owner of %{group} can turn it off.',
  ),
  on_here_read_only_unnamed: s__(
    'SlackIntegration|%{workspace} runs GitLab Duo in the top-level group. An Owner of the top-level group can turn it off.',
  ),
  on_here_by_owners: s__(
    'SlackIntegration|%{workspace} runs GitLab Duo in this group. An Owner of this group can turn it off.',
  ),
  elsewhere: s__(
    "SlackIntegration|%{workspace} runs GitLab Duo in %{group}. Its sessions use that group's settings and credits.",
  ),
  elsewhere_unnamed: s__(
    "SlackIntegration|%{workspace} runs GitLab Duo in another group. Its sessions use that group's settings and credits.",
  ),
};

// Keyed by the notice's `link_kind`.
export const NOTICE_LINKS = {
  settings: s__('SlackIntegration|Open the GitLab for Slack settings of %{group}'),
  owners: s__('SlackIntegration|View the Owners of %{group}'),
  admin: s__('SlackIntegration|Open the Admin area'),
};

// Keyed by requirement ID. A failed check says what's wrong, in the text and in the fix link's
// accessible name.
export const REQUIREMENT_CHECKS = {
  passed: {
    duo_features: s__('SlackIntegration|GitLab Duo is turned on'),
    agent_platform: s__('SlackIntegration|GitLab Duo Agent Platform is turned on'),
    experiment_features: s__('SlackIntegration|Experiment and beta features are turned on'),
  },
  failed: {
    duo_features: s__('SlackIntegration|GitLab Duo is turned off'),
    agent_platform: s__('SlackIntegration|GitLab Duo Agent Platform is turned off'),
    experiment_features: s__('SlackIntegration|Experiment and beta features are turned off'),
  },
};
