<script>
import {
  GlButton,
  GlButtonGroup,
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
} from '@gitlab/ui';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__ } from '~/locale';
import { updateHistory, visitUrl } from '~/lib/utils/url_utility';
import { InternalEvents } from '~/tracking';
import workItemEnableAiPlanningMutation from 'ee/work_items/graphql/work_item_enable_ai_planning.mutation.graphql';
import DuoWorkItemToMrAction from 'ee/ai/shared/widgets/duo_work_item_to_mr_action.vue';
import workplanFlowAvailabilityQuery from 'ee/work_items/graphql/workplan_flow_availability.query.graphql';
import { isWorkplanFlowAvailable, workplanGenerationDisabledReason } from 'ee/work_items/utils';
import {
  IMPLEMENTATION_UNAVAILABLE_MESSAGE,
  IMPLEMENTATION_WITHOUT_WORKPLAN_HELP_PATH,
  WORKPLAN_ACTION_EVENT,
} from './implementation_widget/constants';
import { writeWorkplanUrl } from './implementation_widget/use_workplan_panel_state';
import {
  buildWorkplanPageUrl,
  buildWorkplanQuery,
  trackWorkplanCreateManually,
  trackWorkplanImplement,
} from './implementation_widget/utils';
import WorkplanAvailabilityPopover from './implementation_widget/workplan_availability_popover.vue';
import {
  cancelWorkplanStartRequest,
  requestWorkplanStart,
} from './implementation_widget/workplan_start_request';

const ACTION_PLAN = 'plan';
const ACTION_CREATE_MANUALLY = 'create-manually';
const ACTION_IMPLEMENT = 'implement';

export default {
  name: 'WorkItemPlanCta',
  components: {
    GlButton,
    GlButtonGroup,
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
    DuoWorkItemToMrAction,
    WorkplanAvailabilityPopover,
  },
  mixins: [InternalEvents.mixin()],
  inject: {
    openDetailPanelItemPage: { default: null },
  },
  props: {
    workItem: {
      type: Object,
      required: true,
    },
    isInDrawer: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['error'],
  data() {
    return {
      pendingAction: null,
      workplanFlowAvailable: null,
    };
  },
  apollo: {
    workplanFlowAvailable: {
      query: workplanFlowAvailabilityQuery,
      variables() {
        return { fullPath: this.workItem.namespace?.fullPath };
      },
      update(data) {
        return isWorkplanFlowAvailable(data.project);
      },
      error(error) {
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    generationDisabledReason() {
      return workplanGenerationDisabledReason(this.workplanFlowAvailable);
    },
    isPlanning() {
      return this.pendingAction === ACTION_PLAN;
    },
    isDropdownActionPending() {
      return Boolean(this.pendingAction) && !this.isPlanning;
    },
    projectPath() {
      return this.workItem.namespace?.fullPath;
    },
  },
  methods: {
    async enableAiPlanning() {
      if (this.generationDisabledReason || this.pendingAction) {
        return;
      }

      this.trackEvent(WORKPLAN_ACTION_EVENT, { label: 'plan', property: 'plan_cta' });
      this.pendingAction = ACTION_PLAN;
      // Enabling mounts the workplan widget, which owns the run and its `Preparing...`
      // state, so the request must be in place before it does.
      requestWorkplanStart(this.workItem.id);
      try {
        if (!(await this.enablePlanning())) {
          cancelWorkplanStartRequest(this.workItem.id);
        }
      } catch (error) {
        cancelWorkplanStartRequest(this.workItem.id);
        this.emitEnableError(error);
      } finally {
        this.pendingAction = null;
      }
    },
    async createManually() {
      if (this.pendingAction) {
        return;
      }

      trackWorkplanCreateManually('plan_cta');
      this.pendingAction = ACTION_CREATE_MANUALLY;
      // The widget opens its panel from the URL when it mounts, so the edit intent
      // must be in the URL before enabling planning mounts it.
      const previousUrl = window.location.href;
      if (!this.isInDrawer) {
        writeWorkplanUrl({ editing: true });
      }

      let enabled = false;
      try {
        enabled = await this.enablePlanning();
      } catch (error) {
        this.emitEnableError(error);
      } finally {
        this.pendingAction = null;
      }

      if (!enabled) {
        if (!this.isInDrawer) {
          updateHistory({ url: previousUrl, replace: true });
        }
        return;
      }
      if (this.isInDrawer) {
        this.openWorkplanEditorPage();
      }
    },
    // The drawer cannot open the workplan panel, so the widget's own
    // Create manually goes to the work item page too.
    openWorkplanEditorPage() {
      const { webUrl } = this.workItem;
      if (!webUrl) {
        return;
      }
      try {
        if (this.openDetailPanelItemPage) {
          this.openDetailPanelItemPage(buildWorkplanQuery({ editing: true }));
        } else {
          visitUrl(buildWorkplanPageUrl(webUrl, { editing: true }));
        }
      } catch (error) {
        Sentry.captureException(error);
      }
    },
    onImplementTriggering() {
      // Planning is still off, so there is no readiness score to send.
      trackWorkplanImplement('plan_cta');
      this.pendingAction = ACTION_IMPLEMENT;
    },
    onImplementTriggered() {
      this.pendingAction = null;
    },
    emitEnableError(error) {
      this.$emit(
        'error',
        s__(
          'WorkItem|Something went wrong while enabling planning for this item. Please try again.',
        ),
      );
      Sentry.captureException(error);
    },
    async enablePlanning() {
      const { data } = await this.$apollo.mutate({
        mutation: workItemEnableAiPlanningMutation,
        variables: {
          input: { id: this.workItem.id },
          useWorkItemFeatures: true,
        },
      });

      const { errors } = data.workItemEnableAiPlanning;
      if (errors.length) {
        this.$emit('error', errors.join('\n'));
        return false;
      }
      return true;
    },
  },
  createManuallyItem: {
    text: s__('AgentPlan|Create workplan manually'),
    icon: 'doc-new',
    extraAttrs: { 'data-testid': 'work-item-plan-cta-create-manually' },
  },
  IMPLEMENTATION_UNAVAILABLE_MESSAGE,
  IMPLEMENTATION_WITHOUT_WORKPLAN_HELP_PATH,
};
</script>

<template>
  <span class="gl-inline-flex">
    <gl-button-group>
      <gl-button
        ref="planButton"
        :disabled="Boolean(generationDisabledReason) || isDropdownActionPending || isPlanning"
        accessible-disabled
        icon="tanuki-ai"
        size="small"
        data-testid="work-item-plan-cta"
        @click="enableAiPlanning"
      >
        {{ s__('WorkItem|Plan') }}
      </gl-button>
      <gl-disclosure-dropdown
        :toggle-text="s__('WorkItem|More planning options')"
        :disabled="isPlanning"
        :loading="isDropdownActionPending"
        text-sr-only
        size="small"
        placement="bottom-end"
        data-testid="work-item-plan-cta-dropdown"
      >
        <gl-disclosure-dropdown-item :item="$options.createManuallyItem" @action="createManually" />
        <!-- eslint-disable local-rules/vue-no-web-url -- The Developer flow goal links the work item; webUrl is what the work-item fragment already exposes. -->
        <duo-work-item-to-mr-action
          render-as="dropdown-item"
          :project-path="projectPath"
          :work-item-iid="workItem.iid"
          :work-item-type="workItem.workItemType?.name"
          :work-item-web-url="workItem.webUrl"
          :disabled-flow-message="$options.IMPLEMENTATION_UNAVAILABLE_MESSAGE"
          :disabled-flow-help-path="$options.IMPLEMENTATION_WITHOUT_WORKPLAN_HELP_PATH"
          data-testid="work-item-plan-cta-implement"
          @triggering="onImplementTriggering"
          @triggered="onImplementTriggered"
        />
        <!-- eslint-enable local-rules/vue-no-web-url -->
      </gl-disclosure-dropdown>
    </gl-button-group>
    <workplan-availability-popover
      v-if="generationDisabledReason"
      :target="() => $refs.planButton?.$el"
      :reason="generationDisabledReason"
    />
  </span>
</template>
