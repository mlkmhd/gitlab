<script>
import { MountingPortal } from 'portal-vue';
import { s__ } from '~/locale';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import SessionDetailsDrawer from 'ee/agent_artifacts/components/session_details_drawer.vue';
import { focusPanel } from 'ee/agent_artifacts/utils';
import { auditEventsHref } from 'ee/ai/governance/utils';
import AuditEventsPanelView from './audit_events_panel_view.vue';
import SkillPanelView from './skill_panel_view.vue';
import { PANEL_VIEW_AUDIT_EVENTS, PANEL_VIEW_SESSION, PANEL_VIEW_SKILL } from './constants';

export default {
  name: 'GovernanceSidePanel',
  components: {
    AuditEventsPanelView,
    DynamicPanel,
    MountingPortal,
    SessionDetailsDrawer,
    SkillPanelView,
  },
  props: {
    // Open views, oldest first, as `{ view, props }`. The last one shows, and Back
    // returns to the one before it.
    stack: {
      type: Array,
      required: true,
    },
  },
  emits: ['push', 'back', 'close'],
  data() {
    return {
      selectedEvent: null,
      // Changes when a card opens a new panel, so the list starts over with its filters.
      listKey: 0,
    };
  },
  computed: {
    root() {
      return this.stack[0];
    },
    current() {
      return this.stack[this.stack.length - 1];
    },
    hasList() {
      return this.root.view === PANEL_VIEW_AUDIT_EVENTS;
    },
    isSkillView() {
      return this.root.view === PANEL_VIEW_SKILL;
    },
    showsPanel() {
      return (this.hasList || this.isSkillView) && !this.isSessionView;
    },
    isSessionView() {
      return this.current.view === PANEL_VIEW_SESSION;
    },
    canGoBack() {
      return this.stack.length > 1;
    },
    // A skill opens its vulnerability in full page; a list, the Audit events tab with its filters.
    maximizeUrl() {
      if (this.isSkillView) return this.root.props.href;

      return auditEventsHref(null, this.root.props.filters);
    },
    // The Audit events tab with the same filters, and this session open in its drawer.
    sessionMaximizeUrl() {
      return auditEventsHref(null, {
        ...this.root.props.filters,
        session: this.current.props.session.sessionId,
      });
    },
    // The card names what was clicked; a deep link has no name, so it falls back.
    listTitle() {
      if (this.isSkillView) return this.root.props.title;

      return this.root.props.title || s__('AgentArtifacts|Audit events');
    },
  },
  watch: {
    root() {
      this.listKey += 1;
      this.returnFocusTo = document.activeElement;
    },
    current() {
      this.selectedEvent = null;
      this.focusCurrent();
    },
  },
  created() {
    // Usually the card row that opened the panel; focus returns there on close.
    this.returnFocusTo = document.activeElement;
  },
  mounted() {
    document.addEventListener('keydown', this.handleKeydown);
    this.focusCurrent();
  },
  beforeDestroy() {
    document.removeEventListener('keydown', this.handleKeydown);
    this.returnFocusTo?.focus?.();
  },
  methods: {
    focusCurrent() {
      this.$nextTick(() => {
        if (this.isSessionView) {
          this.$refs.session?.focus();
        } else {
          focusPanel(this.$refs.panel?.$el);
        }
      });
    },
    // The session view closes itself on Escape, so this only covers the panel's own views.
    handleKeydown({ key }) {
      if (
        key !== 'Escape' ||
        this.isSessionView ||
        document.body.classList.contains('modal-open') ||
        document.activeElement?.closest('input, textarea, .gl-new-dropdown')
      ) {
        return;
      }

      this.$emit('close');
    },
    openSession(session) {
      this.$emit('push', { view: PANEL_VIEW_SESSION, props: { session } });
    },
    // In session details, Back first leaves an open audit event, then the session.
    handleSessionBack() {
      if (this.selectedEvent) {
        this.selectedEvent = null;
        return;
      }

      this.$emit('back');
    },
  },
};
</script>

<template>
  <div>
    <mounting-portal v-if="showsPanel" mount-to="#contextual-panel-portal" append>
      <dynamic-panel
        ref="panel"
        :header="listTitle"
        :maximize-url="maximizeUrl"
        data-testid="governance-side-panel"
        @close="$emit('close')"
      >
        <skill-panel-view
          v-if="isSkillView"
          :key="`skill-${listKey}`"
          :vulnerability-id="root.props.vulnerabilityId"
        />
        <audit-events-panel-view
          v-else
          :key="listKey"
          :filters="root.props.filters"
          @open-session="openSession"
        />
      </dynamic-panel>
    </mounting-portal>

    <session-details-drawer
      v-if="isSessionView"
      ref="session"
      :active-item="current.props.session"
      :selected-event="selectedEvent"
      :back-label="canGoBack ? __('Back') : null"
      :maximize-url="sessionMaximizeUrl"
      panel-layout
      @close="$emit('close')"
      @select="selectedEvent = $event"
      @back="handleSessionBack"
    />
  </div>
</template>
