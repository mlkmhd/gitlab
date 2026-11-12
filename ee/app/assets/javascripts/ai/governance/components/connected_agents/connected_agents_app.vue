<script>
import {
  GlAlert,
  GlAvatarLabeled,
  GlAvatarLink,
  GlBadge,
  GlFilteredSearch,
  GlFilteredSearchToken,
  GlIcon,
  GlKeysetPagination,
  GlLink,
  GlLoadingIcon,
  GlTable,
} from '@gitlab/ui';
import { s__, __, formatNumber, sprintf } from '~/locale';
import { OPERATORS_IS } from '~/vue_shared/components/filtered_search_bar/constants';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import TriggeredByToken from 'ee/agent_artifacts/components/tokens/triggered_by_token.vue';
import { AGENT_TYPE_LABELS } from '../../constants';
import { agentLogo, agentLogoClass, formatAgentType } from '../../utils';
import getAiAgentIdentitiesQuery from '../../graphql/queries/get_ai_agent_identities.query.graphql';

const DEFAULT_PAGE_SIZE = 20;

// The sessionCount field stops counting here, and returns one more to show that more exist.
const SESSION_COUNT_LIMIT = 1000;

const TOKEN_TYPE_AGENT = 'agentType';
const TOKEN_TYPE_USER = 'userId';
const TOKEN_TYPE_STATUS = 'status';

// AiExternalAgentType values are the stored agent types in upper snake case, for example
// CLAUDE_CODE for claude-code.
const toStoredAgentType = (value) => value.toLowerCase().replaceAll('_', '-');
const toAgentTypeEnum = (agentType) => agentType.replaceAll('-', '_').toUpperCase();

const STATUS_LABELS = {
  ACTIVE: s__('AiGovernance|Active'),
  INACTIVE: s__('AiGovernance|Inactive'),
  REVOKED: s__('AiGovernance|Revoked'),
};

const STATUS_BADGE_VARIANTS = { ACTIVE: 'success', INACTIVE: 'neutral', REVOKED: 'danger' };

export default {
  name: 'ConnectedAgentsApp',
  components: {
    GlAlert,
    GlAvatarLabeled,
    GlAvatarLink,
    GlBadge,
    GlFilteredSearch,
    GlIcon,
    GlKeysetPagination,
    GlLink,
    GlLoadingIcon,
    GlTable,
    TimeAgoTooltip,
  },
  inject: {
    groupFullPath: { default: '' },
    projectFullPath: { default: '' },
  },
  apollo: {
    identities: {
      query: getAiAgentIdentitiesQuery,
      variables() {
        return this.queryVariables;
      },
      update(data) {
        const container = this.isProject ? data.project : data.group;
        return container?.aiAgentIdentities ?? null;
      },
      result({ data }) {
        if (data) {
          this.hasError = false;
        }
      },
      error() {
        this.hasError = true;
      },
    },
  },
  data() {
    return {
      identities: null,
      filterValue: [],
      filter: {},
      after: null,
      before: null,
      hasError: false,
    };
  },
  computed: {
    isProject() {
      return Boolean(this.projectFullPath);
    },
    queryVariables() {
      return {
        groupFullPath: this.groupFullPath,
        projectFullPath: this.projectFullPath,
        isProject: this.isProject,
        ...this.filter,
        last: this.before ? DEFAULT_PAGE_SIZE : null,
        first: this.before ? null : DEFAULT_PAGE_SIZE,
        after: this.after,
        before: this.before,
      };
    },
    isLoading() {
      return this.$apollo.queries.identities.loading;
    },
    items() {
      return this.identities?.nodes || [];
    },
    pageInfo() {
      return this.identities?.pageInfo || {};
    },
    fields() {
      return this.$options.allFields.filter(({ key }) => !(this.isProject && key === 'project'));
    },
    tokens() {
      return [
        {
          type: TOKEN_TYPE_AGENT,
          icon: 'tanuki-ai',
          title: s__('AiGovernance|Agent'),
          token: GlFilteredSearchToken,
          unique: true,
          operators: OPERATORS_IS,
          options: Object.entries(AGENT_TYPE_LABELS)
            .filter(([agentType]) => agentType !== 'gitlab_duo')
            .map(([agentType, title]) => ({ value: toAgentTypeEnum(agentType), title })),
        },
        {
          type: TOKEN_TYPE_USER,
          icon: 'user',
          title: s__('AiGovernance|Connected by'),
          token: TriggeredByToken,
          unique: true,
          operators: OPERATORS_IS,
          fullPath: this.projectFullPath || this.groupFullPath,
          isProject: this.isProject,
          valueField: 'id',
          defaultUsers: [],
        },
        {
          type: TOKEN_TYPE_STATUS,
          icon: 'status',
          title: s__('AiGovernance|Status'),
          token: GlFilteredSearchToken,
          unique: true,
          operators: OPERATORS_IS,
          options: Object.entries(STATUS_LABELS).map(([value, title]) => ({ value, title })),
        },
      ];
    },
  },
  methods: {
    agentName(agentType) {
      return formatAgentType(toStoredAgentType(agentType));
    },
    logoFor(agentType) {
      return agentLogo(toStoredAgentType(agentType));
    },
    logoClassFor(agentType) {
      return agentLogoClass(toStoredAgentType(agentType));
    },
    statusLabel(status) {
      return STATUS_LABELS[status] ?? status;
    },
    statusVariant(status) {
      return STATUS_BADGE_VARIANTS[status] ?? 'neutral';
    },
    sessionCount(count) {
      if (count > SESSION_COUNT_LIMIT) {
        return sprintf(s__('AiGovernance|%{count}+'), { count: formatNumber(SESSION_COUNT_LIMIT) });
      }
      return formatNumber(count);
    },
    onSubmit(terms) {
      const filter = {};
      terms.forEach((term) => {
        const data = term?.value?.data;
        if (!data) return;

        switch (term.type) {
          case TOKEN_TYPE_AGENT:
            filter.agentTypes = [data];
            break;
          case TOKEN_TYPE_USER:
            filter.userId = data;
            break;
          case TOKEN_TYPE_STATUS:
            filter.status = data;
            break;
          default:
        }
      });
      this.setFilter(filter);
    },
    onClear() {
      this.filterValue = [];
      this.setFilter({});
    },
    setFilter(filter) {
      this.filter = filter;
      this.after = null;
      this.before = null;
    },
    handleNext(endCursor) {
      this.after = endCursor;
      this.before = null;
    },
    handlePrev(startCursor) {
      this.before = startCursor;
      this.after = null;
    },
  },
  allFields: [
    { key: 'agent', label: s__('AiGovernance|Agent') },
    { key: 'user', label: s__('AiGovernance|Connected by') },
    { key: 'project', label: __('Project') },
    { key: 'createdAt', label: s__('AiGovernance|First connected') },
    { key: 'lastSyncedAt', label: s__('AiGovernance|Last active') },
    { key: 'sessionCount', label: s__('AiGovernance|Sessions') },
    { key: 'status', label: s__('AiGovernance|Status') },
  ],
};
</script>

<template>
  <div class="gl-mt-5">
    <gl-filtered-search
      v-model="filterValue"
      class="gl-mb-5"
      :placeholder="s__('AiGovernance|Filter connected agents...')"
      :available-tokens="tokens"
      :clear-button-title="__('Clear')"
      :close-button-title="__('Close')"
      terms-as-tokens
      data-testid="connected-agents-filtered-search"
      @submit="onSubmit"
      @clear="onClear"
    />

    <gl-alert v-if="hasError" variant="danger" :dismissible="false" class="gl-mb-5">
      {{ s__('AiGovernance|Failed to load connected agents.') }}
    </gl-alert>

    <gl-table
      :fields="fields"
      :items="items"
      :busy="isLoading"
      show-empty
      stacked="md"
      class="gl-w-full"
      :tbody-tr-attr="{ 'data-testid': 'connected-agent-row' }"
    >
      <template #table-busy>
        <gl-loading-icon size="lg" class="gl-my-5" />
      </template>

      <template #empty>
        <div class="gl-py-5 gl-text-center" data-testid="connected-agents-empty">
          {{ s__('AiGovernance|No connected agents found.') }}
        </div>
      </template>

      <template #cell(agent)="{ item }">
        <span class="gl-flex gl-items-center gl-gap-2">
          <img
            v-if="logoFor(item.agentType)"
            :src="logoFor(item.agentType)"
            :class="logoClassFor(item.agentType)"
            :alt="''"
            width="16"
            height="16"
            class="gl-shrink-0 gl-object-contain"
            data-testid="connected-agent-logo"
          />
          <gl-icon v-else name="connected" class="gl-shrink-0 gl-text-subtle" />
          <span data-testid="connected-agent-name">{{ agentName(item.agentType) }}</span>
        </span>
      </template>

      <template #cell(user)="{ item }">
        <gl-avatar-link
          v-if="item.user"
          :href="item.user.webPath"
          data-testid="connected-agent-user"
        >
          <gl-avatar-labeled
            :size="24"
            :src="item.user.avatarUrl"
            :label="item.user.name"
            :sub-label="`@${item.user.username}`"
          />
        </gl-avatar-link>
      </template>

      <template #cell(project)="{ item }">
        <gl-link
          v-if="item.project"
          :href="item.project.webPath"
          data-testid="connected-agent-project"
        >
          {{ item.project.nameWithNamespace }}
        </gl-link>
      </template>

      <template #cell(createdAt)="{ item }">
        <time-ago-tooltip :time="item.createdAt" />
      </template>

      <template #cell(lastSyncedAt)="{ item }">
        <time-ago-tooltip v-if="item.lastSyncedAt" :time="item.lastSyncedAt" />
        <span v-else class="gl-text-subtle" data-testid="connected-agent-never-synced">
          {{ s__('AiGovernance|Never') }}
        </span>
      </template>

      <template #cell(sessionCount)="{ item }">
        <span data-testid="connected-agent-session-count">{{
          sessionCount(item.sessionCount)
        }}</span>
      </template>

      <template #cell(status)="{ item }">
        <gl-badge :variant="statusVariant(item.status)" data-testid="connected-agent-status">
          {{ statusLabel(item.status) }}
        </gl-badge>
      </template>
    </gl-table>

    <div
      v-if="pageInfo.hasNextPage || pageInfo.hasPreviousPage"
      class="gl-mt-5 gl-flex gl-justify-center"
    >
      <gl-keyset-pagination v-bind="pageInfo" @prev="handlePrev" @next="handleNext" />
    </div>
  </div>
</template>
