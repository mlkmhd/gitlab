<script>
import {
  GlAvatar,
  GlAvatarLink,
  GlButton,
  GlLink,
  GlToastMixin,
  GlTooltipDirective,
} from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__, sprintf } from '~/locale';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import {
  formatAgentFlowTitle,
  formatAgentFlowTitleTooltip,
  getNumericId,
} from 'ee/ai/duo_agents_platform/utils';
import AgentSessionActions from 'ee/ai/duo_agents_platform/pages/show/components/agent_session_actions.vue';
import { eventHub, REFETCH_SESSIONS, SHOW_SESSION } from 'ee/ai/events/panel';
import { restartWorkflow } from 'ee/rest_api';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import duoChatAvailableQuery from '../../graphql/duo_chat_available.query.graphql';

export default {
  name: 'AgentSessionRow',
  components: {
    AgentSessionActions,
    GlAvatar,
    GlAvatarLink,
    GlButton,
    GlLink,
    TimeAgoTooltip,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [GlToastMixin, glFeatureFlagsMixin()],
  props: {
    session: {
      type: Object,
      required: true,
    },
    showViewDetails: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  data() {
    return {
      duoChatAvailable: false,
      isRetrying: false,
    };
  },
  apollo: {
    duoChatAvailable: {
      query: duoChatAvailableQuery,
      update(data) {
        return data?.currentUser?.duoChatAvailable ?? false;
      },
      error() {
        this.duoChatAvailable = false;
      },
    },
  },
  computed: {
    numericId() {
      return getIdFromGraphQLId(this.session.id);
    },
    sessionUrl() {
      return this.session.webPath || null;
    },
    title() {
      return formatAgentFlowTitle(this.session.title, this.session.workflowDefinition);
    },
    canOpenSession() {
      return Boolean(this.sessionUrl) || this.duoChatAvailable;
    },
    titleComponent() {
      if (this.sessionUrl) return GlLink;
      return this.duoChatAvailable ? GlButton : 'span';
    },
    titleAttributes() {
      if (this.sessionUrl) return { href: this.sessionUrl };
      return this.duoChatAvailable
        ? { variant: 'link', buttonTextClasses: 'gl-truncate' }
        : { tabindex: 0 };
    },
    titleTooltip() {
      return formatAgentFlowTitleTooltip(this.title, this.numericId);
    },
    user() {
      return this.session.user || null;
    },
    userId() {
      return getNumericId(this.user?.id);
    },
    canRestartWorkflow() {
      return Boolean(this.session.userPermissions?.restartDuoWorkflow);
    },
    retryAriaLabel() {
      return sprintf(s__('DuoAgentPlatform|Retry session %{title}'), { title: this.title }, false);
    },
    canRetrySession() {
      return (
        Boolean(this.glFeatures.dapSessionRestarts) &&
        this.canRestartWorkflow &&
        !this.session.restartedAs
      );
    },
    retryUrl() {
      return this.session.restartedAs?.webPath || null;
    },
    showViewRetry() {
      return Boolean(this.glFeatures.dapSessionRestarts) && Boolean(this.retryUrl);
    },
    viewRetryAriaLabel() {
      return sprintf(
        s__('DuoAgentPlatform|View retry of session %{title}'),
        { title: this.title },
        false,
      );
    },
  },
  methods: {
    openSession(event, id = this.numericId) {
      if (!this.duoChatAvailable) return;
      if (event.metaKey || event.ctrlKey || event.shiftKey) return;

      event.preventDefault();
      eventHub.$emit(SHOW_SESSION, { id });
    },
    openRetry(event) {
      this.openSession(event, getIdFromGraphQLId(this.session.restartedAs.id));
    },
    async retrySession() {
      this.isRetrying = true;

      try {
        await restartWorkflow(this.numericId);

        eventHub.$emit(REFETCH_SESSIONS);
        this.$el.ariaNotify(s__('DuoAgentPlatform|Session has been restarted successfully.'));
      } catch (error) {
        Sentry.captureException(error);
        this.$toast.show(s__('DuoAgentPlatform|Failed to retry session. Please try again.'));
      } finally {
        this.isRetrying = false;
      }
    },
  },
};
</script>

<template>
  <div
    class="gl-flex gl-items-center gl-justify-between gl-gap-3 gl-px-4 gl-py-3"
    data-testid="agent-session-row"
  >
    <div class="gl-flex gl-min-w-0 gl-items-center">
      <component
        :is="titleComponent"
        v-gl-tooltip
        v-bind="titleAttributes"
        :title="titleTooltip"
        class="gl-truncate"
        :class="{ 'gl-text-subtle': !canOpenSession }"
        data-testid="session-title"
        @click="openSession"
      >
        {{ title }}
      </component>
    </div>
    <div class="gl-flex gl-shrink-0 gl-items-center gl-gap-3 gl-whitespace-nowrap">
      <time-ago-tooltip
        v-if="session.updatedAt"
        :time="session.updatedAt"
        class="gl-text-sm gl-text-subtle"
        data-testid="session-updated-at"
      />
      <gl-button
        v-if="canOpenSession && showViewDetails"
        :href="sessionUrl"
        size="small"
        variant="confirm"
        category="tertiary"
        data-testid="session-view-details-button"
        @click="openSession"
      >
        {{ s__('DuoAgentPlatform|View details') }}
      </gl-button>
      <gl-avatar-link
        v-if="user"
        v-gl-tooltip.bottom
        :href="user.webPath"
        :title="user.name"
        :data-user-id="userId"
        :data-username="user.username"
        class="js-user-link"
        data-testid="session-triggered-user"
      >
        <gl-avatar
          :src="user.avatarUrl"
          :entity-name="user.name"
          :alt="user.name"
          :size="16"
          shape="circle"
        />
      </gl-avatar-link>
      <gl-link
        v-if="showViewRetry"
        :href="retryUrl"
        :aria-label="viewRetryAriaLabel"
        class="gl-text-sm"
        data-testid="session-view-retry-link"
        @click="openRetry"
      >
        {{ s__('DuoAgentPlatform|View retry') }}
      </gl-link>
      <agent-session-actions
        v-if="canRetrySession"
        :status="session.status"
        :can-restart-workflow="canRestartWorkflow"
        :is-retrying="isRetrying"
        display-minimal
        icon-button-category="tertiary"
        :retry-aria-label="retryAriaLabel"
        @retry-session="retrySession"
      />
    </div>
  </div>
</template>
