<script>
import { GlBadge, GlIcon, GlLink, GlSprintf, GlToggle, GlToastMixin } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import axios from '~/lib/utils/axios_utils';
import { convertObjectPropsToCamelCase } from '~/lib/utils/common_utils';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_action';
import { createAlert } from '~/alert';
import { s__, sprintf } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import { BADGES, NOTICE_LINKS, NOTICES } from '../slack_duo_copy';
import {
  STATE_ON_HERE,
  STATE_OFF,
  STATE_ELSEWHERE,
  STATE_INSTANCE_MANAGED,
} from '../slack_duo_constants';
import SlackDuoPermissionsAlert from './slack_duo_permissions_alert.vue';
import SlackDuoRequirements from './slack_duo_requirements.vue';

const SCOPE_GROUP = 'group';

// The top-level group page shows this page's own Slack workspace. Subgroup and project pages only point
// to where it's decided. The backend decides every state.
export default {
  name: 'SlackDuoSection',
  components: {
    GlBadge,
    GlIcon,
    GlLink,
    GlSprintf,
    GlToggle,
    SlackDuoPermissionsAlert,
    SlackDuoRequirements,
  },
  mixins: [GlToastMixin],
  props: {
    slackDuo: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      duo: this.slackDuo,
      savingTeamId: null,
      ids: {
        mainHelp: uniqueId('slack-duo-main-help-'),
        mainSeatNote: uniqueId('slack-duo-main-seat-note-'),
      },
    };
  },
  computed: {
    isGroupPage() {
      return this.duo.scope === SCOPE_GROUP;
    },
    workspaces() {
      return this.duo.workspaces || [];
    },
    main() {
      if (!this.isGroupPage || !this.duo.ownTeamId) return null;
      return this.workspaces.find((workspace) => workspace.teamId === this.duo.ownTeamId) || null;
    },
    mainHasToggle() {
      return Boolean(
        this.main && this.main.canManage && [STATE_ON_HERE, STATE_OFF].includes(this.main.state),
      );
    },
    // The toggle's label only names the workspace; these say what turning it on does.
    mainDescribedBy() {
      return [this.ids.mainHelp, this.duo.seatsRequired && this.ids.mainSeatNote]
        .filter(Boolean)
        .join(' ');
    },
    mainWorkspaceName() {
      return this.main ? this.main.teamName : this.duo.teamName;
    },
    failedRequirements() {
      return (this.duo.requirements || []).filter((requirement) => !requirement.ok);
    },
    // Slack doesn't send mentions of @GitLab to an app without `app_mentions:read`.
    mainNeedsReinstall() {
      return Boolean(this.main && !this.main.slackPermissionsOk);
    },
    badge() {
      const state = this.isGroupPage ? this.main?.state : this.duo.state;

      switch (state) {
        case STATE_ON_HERE:
          return this.failedRequirements.length || this.mainNeedsReinstall
            ? { text: BADGES.needsAttention, variant: 'warning' }
            : { text: BADGES.on, variant: 'success' };
        case STATE_OFF:
          return { text: BADGES.off, variant: 'neutral' };
        case STATE_ELSEWHERE:
          return { text: BADGES.elsewhere, variant: 'info' };
        case STATE_INSTANCE_MANAGED:
          return { text: BADGES.admin, variant: 'info' };
        default:
          return null;
      }
    },
    mainHelp() {
      return this.main?.state === STATE_ON_HERE
        ? s__(
            'SlackIntegration|All GitLab Duo sessions from %{workspace} run in this group and use its GitLab Duo settings and credits. Members of this group with at least the Developer role can use it.',
          )
        : s__(
            'SlackIntegration|Turn on to run all GitLab Duo sessions from %{workspace} in this group, with its GitLab Duo settings and credits. Members of this group with at least the Developer role can use it.',
          );
    },
    // What the page says when there's no toggle for its own workspace.
    notice() {
      if (this.isGroupPage) {
        if (this.main) return this.mainHasToggle ? null : this.rowNotice(this.main);
        // Workspaces installed lower in the group get no toggle here: installing the app on this group does.
        return { message: NOTICES.not_connected };
      }

      const { notice } = this.duo;
      if (!notice) return null;

      const unnamedKey = `${notice.key}_unnamed`;
      const key = !notice.groupName && NOTICES[unnamedKey] ? unnamedKey : notice.key;

      return { message: NOTICES[key], groupName: notice.groupName, link: this.noticeLink(notice) };
    },
  },
  methods: {
    noticeLink({ linkKind, linkPath, groupName }) {
      if (!linkPath || !NOTICE_LINKS[linkKind]) return null;
      return { text: sprintf(NOTICE_LINKS[linkKind], { group: groupName }, false), href: linkPath };
    },
    // What the page's own workspace says when the viewer can't change it here.
    rowNotice(workspace) {
      const group = workspace.duoGroup;

      switch (workspace.state) {
        case STATE_ON_HERE:
          return { message: NOTICES.on_here_by_owners };
        case STATE_ELSEWHERE:
          return group
            ? {
                message: NOTICES.elsewhere,
                groupName: group.name,
                link: this.noticeLink({ ...group, groupName: group.name }),
              }
            : { message: NOTICES.elsewhere_unnamed };
        case STATE_INSTANCE_MANAGED:
          return {
            message: this.instanceManagedNotice(workspace),
            groupName: group?.name,
            link: this.noticeLink({ linkKind: 'admin', linkPath: this.duo.adminIntegrationPath }),
          };
        default:
          return { message: NOTICES.off_by_owners };
      }
    },
    // `duoGroup` is null both when no group is chosen and when the viewer can't see the chosen one.
    instanceManagedNotice({ duoGroup, duoOn }) {
      if (duoGroup) return NOTICES.instance_managed_on;
      return duoOn ? NOTICES.instance_managed_on_unnamed : NOTICES.instance_managed_off;
    },
    isOn(workspace) {
      return workspace.state === STATE_ON_HERE;
    },
    toggleLabel(workspace) {
      return sprintf(
        s__('SlackIntegration|GitLab Duo for %{workspace}'),
        { workspace: workspace.teamName },
        false,
      );
    },
    // A change answers with the changed row.
    withUpdatedRow({ updatedWorkspace, ...data }) {
      return {
        ...data,
        workspaces: this.workspaces.map((workspace) =>
          workspace.teamId === updatedWorkspace?.teamId ? updatedWorkspace : workspace,
        ),
      };
    },
    async onToggle(workspace, enabled) {
      // GlToggle still emits `change` while `isLoading`, so a second press would save again.
      if (this.savingTeamId === workspace.teamId) return;

      if (!enabled) {
        const confirmed = await confirmAction(
          sprintf(
            s__(
              'SlackIntegration|Turn off GitLab Duo for %{workspace}? New mentions of @GitLab get no answer until an Owner turns it on again. Sessions that already run continue.',
            ),
            { workspace: workspace.teamName },
            false,
          ),
          {
            primaryBtnText: s__('SlackIntegration|Turn off GitLab Duo'),
            primaryBtnVariant: 'danger',
          },
        );
        if (!confirmed) return;
      }

      this.savingTeamId = workspace.teamId;
      try {
        const { data } = await axios.put(this.duo.updatePath, {
          enabled,
          team_id: workspace.teamId,
        });
        this.duo = this.withUpdatedRow(convertObjectPropsToCamelCase(data, { deep: true }));
        this.$toast.show(
          enabled
            ? s__('SlackIntegration|GitLab Duo turned on for this Slack workspace.')
            : s__('SlackIntegration|GitLab Duo turned off for this Slack workspace.'),
        );
      } catch (error) {
        const message = error.response?.data?.message;
        createAlert({
          message:
            message || s__('SlackIntegration|Could not update GitLab Duo for Slack. Try again.'),
          ...(message ? {} : { error, captureError: true }),
        });
      } finally {
        this.savingTeamId = null;
      }
    },
  },
  learnMorePath: helpPagePath('user/project/integrations/gitlab_slack_application', {
    anchor: 'gitlab-duo',
  }),
};
</script>

<template>
  <section
    class="gl-mb-6 gl-rounded-base gl-border-1 gl-border-solid gl-border-default gl-p-5"
    aria-labelledby="slack-duo-title"
    data-testid="slack-duo-section"
  >
    <div class="gl-mb-3 gl-flex gl-items-center gl-gap-3">
      <gl-icon name="tanuki-ai" :size="24" />
      <h2 id="slack-duo-title" class="gl-heading-4 gl-m-0">{{ __('GitLab Duo') }}</h2>
      <gl-badge v-if="badge" :variant="badge.variant" data-testid="slack-duo-badge">{{
        badge.text
      }}</gl-badge>
    </div>
    <p class="gl-text-subtle">
      {{
        s__(
          'SlackIntegration|Mention @GitLab in Slack to ask questions and have GitLab Duo act in GitLab for you, with the permissions of the person who mentions it.',
        )
      }}
      <gl-link :href="$options.learnMorePath" target="_blank">{{ __('Learn more') }}</gl-link>
    </p>

    <slack-duo-permissions-alert
      v-if="mainNeedsReinstall"
      class="gl-mb-4"
      :team-name="main.teamName"
      :reinstall-path="main.reinstallPath"
      data-testid="slack-duo-permissions"
    />

    <div v-if="mainWorkspaceName" data-testid="slack-duo-main">
      <p class="gl-mb-2 gl-font-bold" data-testid="slack-duo-main-title">
        <gl-sprintf :message="s__('SlackIntegration|GitLab Duo for %{workspace}')">
          <template #workspace>{{ mainWorkspaceName }}</template>
        </gl-sprintf>
      </p>
      <div v-if="mainHasToggle" class="gl-flex gl-items-start gl-justify-between gl-gap-5">
        <div>
          <p :id="ids.mainHelp" class="gl-mb-0 gl-text-subtle" data-testid="slack-duo-toggle-help">
            <gl-sprintf :message="mainHelp">
              <template #workspace>
                <strong>{{ main.teamName }}</strong>
              </template>
            </gl-sprintf>
          </p>
          <p
            v-if="duo.seatsRequired"
            :id="ids.mainSeatNote"
            class="gl-mb-0 gl-mt-2"
            data-testid="slack-duo-seat-note"
          >
            {{ s__('SlackIntegration|Only members with active GitLab Duo seats can use @GitLab.') }}
          </p>
        </div>
        <gl-toggle
          :value="isOn(main)"
          :is-loading="savingTeamId === main.teamId"
          :label="toggleLabel(main)"
          :aria-describedby="mainDescribedBy"
          label-position="hidden"
          data-testid="slack-duo-toggle"
          @change="(enabled) => onToggle(main, enabled)"
        />
      </div>
    </div>

    <p v-if="notice" class="gl-mb-0" data-testid="slack-duo-notice">
      <gl-sprintf :message="notice.message">
        <template #workspace>
          <strong>{{ mainWorkspaceName }}</strong>
        </template>
        <template #group>
          <strong>{{ notice.groupName }}</strong>
        </template>
      </gl-sprintf>
      <gl-link
        v-if="notice.link"
        :href="notice.link.href"
        class="gl-ml-1"
        data-testid="slack-duo-notice-link"
        >{{ notice.link.text }}</gl-link
      >
    </p>

    <slack-duo-requirements
      v-if="duo.requirements && duo.requirements.length"
      class="gl-mt-5"
      :requirements="duo.requirements"
      :group-settings-path="duo.groupSettingsPath"
      :instance-settings-path="duo.instanceSettingsPath"
      :slack-ready="!mainNeedsReinstall"
    />
  </section>
</template>
