<script>
import {
  GlAvatarLabeled,
  GlBadge,
  GlButton,
  GlCollapsibleListbox,
  GlIcon,
  GlLink,
  GlSprintf,
  GlToastMixin,
} from '@gitlab/ui';
import { debounce, uniqueId } from 'lodash-es';
import axios from '~/lib/utils/axios_utils';
import { convertObjectPropsToCamelCase } from '~/lib/utils/common_utils';
import { DEFAULT_DEBOUNCE_AND_THROTTLE_MS } from '~/lib/utils/constants';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_action';
import { createAlert } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { __, s__, sprintf } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import { getGroups } from '~/rest_api';
import { BADGES, NOTICES } from '../slack_duo_copy';
import { STATE_NOT_CONNECTED, STATE_ON } from '../slack_duo_constants';
import SlackDuoPermissionsAlert from './slack_duo_permissions_alert.vue';
import SlackDuoRequirements from './slack_duo_requirements.vue';

// The Admin area's GitLab for Slack page: the administrator picks the top-level group that runs GitLab Duo for
// the workspace connected for the whole instance. Workspaces that groups installed are decided on their pages.
export default {
  name: 'SlackDuoAdminSection',
  components: {
    GlAvatarLabeled,
    GlBadge,
    GlButton,
    GlCollapsibleListbox,
    GlIcon,
    GlLink,
    GlSprintf,
    SlackDuoPermissionsAlert,
    SlackDuoRequirements,
  },
  mixins: [GlToastMixin],
  props: {
    slackDuoAdmin: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      duo: this.slackDuoAdmin,
      groups: [],
      searchTerm: '',
      latestSearch: null,
      searchFailed: false,
      searching: false,
      saving: false,
      labelId: uniqueId('slack-duo-admin-picker-label-'),
    };
  },
  computed: {
    connected() {
      return this.duo.state !== STATE_NOT_CONNECTED;
    },
    isOn() {
      return this.duo.state === STATE_ON;
    },
    failedRequirements() {
      return (this.duo.requirements || []).filter((requirement) => !requirement.ok);
    },
    needsReinstall() {
      return this.connected && !this.duo.slackPermissionsOk;
    },
    badge() {
      if (!this.connected) return null;
      if (!this.isOn) return { text: BADGES.off, variant: 'neutral' };

      return this.failedRequirements.length || this.needsReinstall
        ? { text: BADGES.needsAttention, variant: 'warning' }
        : { text: BADGES.on, variant: 'success' };
    },
    pickerLabel() {
      return sprintf(
        s__('SlackIntegration|Top-level group that runs GitLab Duo for %{workspace}'),
        { workspace: this.duo.teamName },
        false,
      );
    },
    toggleText() {
      return this.duo.duoGroup
        ? this.duo.duoGroup.name
        : s__('SlackIntegration|Choose a top-level group');
    },
    noResultsText() {
      return this.searchFailed
        ? s__('SlackIntegration|Could not load groups. Try again.')
        : __('No results found');
    },
    items() {
      return this.groups.map((group) => ({
        value: group.id,
        text: group.full_name,
        fullPath: group.full_path,
        avatarUrl: group.avatar_url,
      }));
    },
  },
  created() {
    this.debouncedSearch = debounce(this.search, DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
  },
  beforeDestroy() {
    this.debouncedSearch.cancel();
  },
  methods: {
    onSearch(term) {
      this.searchTerm = term;
      this.debouncedSearch(term);
    },
    async search(term) {
      // A slow answer to an earlier term must not replace the answer to the latest one.
      this.latestSearch = term;
      this.searching = true;
      try {
        const { data } = await getGroups(term, {
          top_level_only: true,
          active: true,
          order_by: 'name',
        });
        if (this.latestSearch !== term) return;
        this.groups = data;
        this.searchFailed = false;
      } catch (error) {
        if (this.latestSearch !== term) return;
        this.groups = [];
        this.searchFailed = true;
        Sentry.captureException(error);
      } finally {
        if (this.latestSearch === term) this.searching = false;
      }
    },
    async choose(groupId) {
      const group = this.items.find((item) => item.value === groupId);
      if (!group || groupId === this.duo.duoGroup?.id) return;

      const { teamName: workspace, duoGroup } = this.duo;
      const confirmation = duoGroup
        ? {
            message: sprintf(
              s__(
                'SlackIntegration|Move GitLab Duo from %{from} to %{to}? New sessions from Slack run in %{to}. Sessions that already run continue in %{from}.',
              ),
              { from: duoGroup.name, to: group.text },
              false,
            ),
            primaryBtnText: s__('SlackIntegration|Move GitLab Duo'),
          }
        : {
            message: sprintf(
              s__(
                'SlackIntegration|Run GitLab Duo for %{workspace} in %{group}? Sessions from this Slack workspace use its GitLab Duo settings and credits. Only members with at least the Developer role in %{group} can use it.',
              ),
              { workspace, group: group.text },
              false,
            ),
            primaryBtnText: s__('SlackIntegration|Turn on GitLab Duo'),
          };
      const confirmed = await confirmAction(confirmation.message, {
        primaryBtnText: confirmation.primaryBtnText,
      });
      if (!confirmed) return;

      await this.update(group.value, s__('SlackIntegration|GitLab Duo in Slack updated.'));
    },
    async turnOff() {
      const message = sprintf(
        s__(
          'SlackIntegration|Turn off GitLab Duo for %{workspace}? New mentions of @GitLab get no answer until you choose a group again. Sessions that already run continue.',
        ),
        { workspace: this.duo.teamName },
        false,
      );
      const confirmed = await confirmAction(message, {
        primaryBtnText: s__('SlackIntegration|Turn off GitLab Duo'),
        primaryBtnVariant: 'danger',
      });
      if (!confirmed) return;

      await this.update(
        null,
        s__('SlackIntegration|GitLab Duo turned off for this Slack workspace.'),
      );
    },
    async update(groupId, successMessage) {
      this.saving = true;
      try {
        const { data } = await axios.put(this.duo.updatePath, {
          team_id: this.duo.teamId,
          group_id: groupId,
        });
        this.duo = convertObjectPropsToCamelCase(data, { deep: true });
        this.$toast.show(successMessage);
      } catch (error) {
        const message = error.response?.data?.message;
        createAlert({
          message:
            message || s__('SlackIntegration|Could not update GitLab Duo for Slack. Try again.'),
          ...(message ? {} : { error, captureError: true }),
        });
      } finally {
        this.saving = false;
      }
    },
  },
  NOTICES,
  learnMorePath: helpPagePath('user/project/integrations/gitlab_slack_application', {
    anchor: 'gitlab-duo',
  }),
};
</script>

<template>
  <section
    class="gl-mb-6 gl-rounded-base gl-border-1 gl-border-solid gl-border-default gl-p-5"
    aria-labelledby="slack-duo-admin-title"
    data-testid="slack-duo-admin-section"
  >
    <div class="gl-mb-3 gl-flex gl-items-center gl-gap-3">
      <gl-icon name="tanuki-ai" :size="24" />
      <h2 id="slack-duo-admin-title" class="gl-heading-4 gl-m-0">{{ __('GitLab Duo') }}</h2>
      <gl-badge v-if="badge" :variant="badge.variant" data-testid="slack-duo-admin-badge">{{
        badge.text
      }}</gl-badge>
    </div>
    <p class="gl-text-subtle">
      {{
        s__(
          'SlackIntegration|Each Slack workspace runs GitLab Duo in one top-level group. You decide for the workspace connected for the whole instance.',
        )
      }}
      <gl-link :href="$options.learnMorePath" target="_blank">{{ __('Learn more') }}</gl-link>
    </p>

    <p v-if="!connected" class="gl-mb-0" data-testid="slack-duo-admin-not-connected">
      {{ $options.NOTICES.not_connected }}
    </p>

    <template v-else>
      <slack-duo-permissions-alert
        v-if="needsReinstall"
        class="gl-mb-4"
        :team-name="duo.teamName"
        :reinstall-path="duo.reinstallPath"
        data-testid="slack-duo-admin-permissions"
      />

      <p class="gl-mb-2 gl-font-bold" data-testid="slack-duo-admin-title-workspace">
        <gl-sprintf :message="s__('SlackIntegration|GitLab Duo for %{workspace}')">
          <template #workspace>{{ duo.teamName }}</template>
        </gl-sprintf>
      </p>
      <p class="gl-mb-3 gl-text-subtle" data-testid="slack-duo-admin-help">
        <gl-sprintf
          :message="
            s__(
              'SlackIntegration|%{workspace} is connected for the whole instance. Choose the top-level group where its GitLab Duo sessions run and use its GitLab Duo settings and credits. Only members of that group with at least the Developer role can use it.',
            )
          "
        >
          <template #workspace>
            <strong>{{ duo.teamName }}</strong>
          </template>
        </gl-sprintf>
        <template v-if="duo.seatsRequired">{{
          s__('SlackIntegration|Only members with active GitLab Duo seats can use @GitLab.')
        }}</template>
      </p>

      <span :id="labelId" class="gl-sr-only">{{ pickerLabel }}</span>
      <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-3">
        <gl-collapsible-listbox
          :selected="duo.duoGroup ? duo.duoGroup.id : null"
          :items="items"
          :toggle-text="toggleText"
          :toggle-aria-labelled-by="labelId"
          :list-aria-labelled-by="labelId"
          :searching="searching"
          :loading="saving"
          :search-placeholder="s__('SlackIntegration|Search groups')"
          :no-results-text="noResultsText"
          searchable
          data-testid="slack-duo-admin-group-picker"
          @shown="search(searchTerm)"
          @search="onSearch"
          @select="choose"
        >
          <template #list-item="{ item }">
            <gl-avatar-labeled
              :label="item.text"
              :sub-label="item.fullPath"
              :entity-name="item.text"
              :entity-id="item.value"
              :src="item.avatarUrl"
              shape="rect"
              :size="32"
            />
          </template>
        </gl-collapsible-listbox>
        <gl-button
          v-if="duo.duoGroup"
          category="tertiary"
          variant="danger"
          :loading="saving"
          data-testid="slack-duo-admin-turn-off"
          @click="turnOff"
          >{{ s__('SlackIntegration|Turn off GitLab Duo') }}</gl-button
        >
      </div>

      <slack-duo-requirements
        v-if="duo.requirements && duo.requirements.length"
        class="gl-mt-5"
        :requirements="duo.requirements"
        :group-settings-path="duo.groupSettingsPath"
        :instance-settings-path="duo.instanceSettingsPath"
        :slack-ready="!needsReinstall"
      />
    </template>
  </section>
</template>
