<script>
import { GlAvatar, GlIcon, GlLink } from '@gitlab/ui';
import { s__, n__ } from '~/locale';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import getDeveloperActivityQuery from 'ee/ai/governance/graphql/queries/get_developer_activity.query.graphql';
import { AGENT_CLASS_ALL, TIMEFRAME_LAST_SEVEN_DAYS } from 'ee/ai/governance/constants';
import { auditEventsFilters, auditEventsHref } from 'ee/ai/governance/utils';
import { PANEL_VIEW_AUDIT_EVENTS } from '../../side_panel/constants';
import DashboardListCard from './dashboard_list_card.vue';

const LIMIT = 5;

export default {
  name: 'DeveloperActivityCard',
  components: {
    DashboardListCard,
    GlAvatar,
    GlIcon,
    GlLink,
  },
  inject: {
    groupFullPath: { default: null },
    projectFullPath: { default: null },
    openGovernancePanel: { default: null },
  },
  props: {
    agentClass: {
      type: String,
      required: false,
      default: AGENT_CLASS_ALL,
    },
    timeframe: {
      type: String,
      required: false,
      default: TIMEFRAME_LAST_SEVEN_DAYS,
    },
  },
  apollo: {
    topUsers: {
      query: getDeveloperActivityQuery,
      variables() {
        return {
          groupFullPath: this.groupFullPath || '',
          projectFullPath: this.projectFullPath || '',
          isProject: this.isProjectMode,
          limit: LIMIT,
          agentClass: this.agentClass,
          timeframe: this.timeframe,
        };
      },
      update(data) {
        return (data.project ?? data.group)?.aiGovernanceMetrics?.topUsers || [];
      },
      error() {
        this.hasError = true;
      },
    },
  },
  data() {
    return {
      topUsers: [],
      hasError: false,
    };
  },
  computed: {
    isProjectMode() {
      return Boolean(this.projectFullPath);
    },
    loading() {
      return this.$apollo.queries.topUsers.loading;
    },
    users() {
      // AiGovernanceUserActivity.user is nullable (deleted/inaccessible user),
      // so skip entries we can't resolve rather than throwing on node.user.
      return (this.topUsers || [])
        .filter((node) => node.user)
        .map((node) => {
          const filters = { triggeredByUserId: node.user.id, agentClass: this.agentClass };

          return {
            id: node.user.id,
            entityId: getIdFromGraphQLId(node.user.id),
            name: node.user.name,
            sessions: n__('AiGovernance|%d session', 'AiGovernance|%d sessions', node.sessionCount),
            // The "Triggered by" filter with the card's date window and agent class, for
            // the side panel, or as a deep link to the Audit events tab (the
            // filtered search seeds itself from these params).
            filters: auditEventsFilters(this.timeframe, filters),
            href: auditEventsHref(this.timeframe, filters),
          };
        });
    },
    isEmpty() {
      return !this.loading && !this.hasError && this.users.length === 0;
    },
    errorText() {
      return this.hasError ? s__('AiGovernance|Failed to load developer activity.') : '';
    },
  },
  methods: {
    // A modified click keeps the link, so the Audit events tab can still open in a new tab.
    openDeveloper(event, user) {
      if (!this.openGovernancePanel || event.metaKey || event.ctrlKey || event.shiftKey) return;

      event.preventDefault();
      this.openGovernancePanel(PANEL_VIEW_AUDIT_EVENTS, {
        filters: user.filters,
        title: user.name,
      });
    },
  },
  i18n: {
    title: s__('AiGovernance|Most active developers using agents'),
    viewAll: s__('AiGovernance|View all users'),
    empty: s__('AiGovernance|No recent developer activity.'),
  },
  viewAllHref: '?tab=agent-artifacts',
};
</script>

<template>
  <dashboard-list-card
    :title="$options.i18n.title"
    :view-all-text="$options.i18n.viewAll"
    :view-all-href="$options.viewAllHref"
    :loading="loading"
    :error-text="errorText"
    :is-empty="isEmpty"
    :empty-text="$options.i18n.empty"
    tracking-label="developer_activity"
  >
    <li
      v-for="user in users"
      :key="user.id"
      class="gl-border-b gl-border-section last:gl-border-b-0"
    >
      <gl-link
        :href="user.href"
        class="gl-flex gl-items-center gl-justify-between gl-gap-3 gl-p-4 gl-text-default hover:gl-bg-strong hover:gl-no-underline"
        data-testid="developer-activity-row"
        data-event-tracking="click_card_link_on_ai_governance_dashboard"
        data-event-label="developer_activity"
        data-event-property="row"
        @click="openDeveloper($event, user)"
      >
        <span class="gl-flex gl-min-w-0 gl-items-center gl-gap-3">
          <gl-avatar :entity-id="user.entityId" :entity-name="user.name" :size="24" />
          <span class="gl-truncate gl-font-bold">{{ user.name }}</span>
        </span>
        <span class="gl-flex gl-shrink-0 gl-items-center gl-gap-2 gl-text-sm gl-text-subtle">
          {{ user.sessions }}
          <gl-icon name="chevron-right" />
        </span>
      </gl-link>
    </li>
  </dashboard-list-card>
</template>
