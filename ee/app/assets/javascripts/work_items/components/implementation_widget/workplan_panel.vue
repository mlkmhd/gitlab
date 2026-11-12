<script>
import {
  GlAlert,
  GlButton,
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
  GlSprintf,
  GlTooltipDirective,
} from '@gitlab/ui';
import { MountingPortal } from 'portal-vue';
import { s__ } from '~/locale';
import DuoWorkItemToMrAction from 'ee/ai/shared/widgets/duo_work_item_to_mr_action.vue';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import WorkplanView from './workplan_view.vue';
import WorkplanEditor from './workplan_editor.vue';
import WorkplanAvailabilityPopover from './workplan_availability_popover.vue';
import {
  WORKPLAN_GOAL_PREFIX,
  WORKPLAN_SOURCE,
  GENERATE_MR_BUTTON_OPTIONS,
  IMPLEMENTATION_UNAVAILABLE_MESSAGE,
  IMPLEMENTATION_HELP_PATH,
} from './constants';
import {
  isValidReadinessScore,
  trackWorkplanCreateManually,
  trackWorkplanImplement,
} from './utils';

export default {
  name: 'WorkplanPanel',
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  components: {
    DynamicPanel,
    GlAlert,
    GlButton,
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
    GlSprintf,
    MountingPortal,
    DuoWorkItemToMrAction,
    WorkplanView,
    WorkplanEditor,
    WorkplanAvailabilityPopover,
    TimeAgoTooltip,
  },
  inject: ['fullPath'],
  inheritAttrs: false,
  props: {
    generationDisabledReason: {
      type: String,
      required: true,
    },
    open: {
      type: Boolean,
      required: true,
    },
    canUpdate: {
      type: Boolean,
      required: true,
    },
    savedContent: {
      type: String,
      required: true,
    },
    savedContentHtml: {
      type: String,
      required: true,
    },
    updatedAt: {
      type: String,
      required: false,
      default: null,
    },
    draftContent: {
      type: String,
      required: true,
    },
    isEditing: {
      type: Boolean,
      required: true,
    },
    isSaving: {
      type: Boolean,
      required: true,
    },
    isLoading: {
      type: Boolean,
      required: true,
    },
    hasContentError: {
      type: Boolean,
      required: true,
    },
    isFlowActive: {
      type: Boolean,
      required: false,
      default: false,
    },
    isActionInFlight: {
      type: Boolean,
      required: false,
      default: false,
    },
    canImplement: {
      type: Boolean,
      required: true,
    },
    canRunWorkplan: {
      type: Boolean,
      required: true,
    },
    workItemIid: {
      type: [String, Number],
      required: true,
    },
    workItemType: {
      type: String,
      required: true,
    },
    workItemWebUrl: {
      type: String,
      required: true,
    },
    readinessScore: {
      type: Number,
      required: false,
      default: null,

      validator: isValidReadinessScore,
    },
  },
  emits: [
    'close',
    'save',
    'delete',
    'draft-change',
    'start-edit',
    'cancel-edit',
    'regenerate',
    'generate',
    'retry',
    'implementation-started',
  ],
  computed: {
    isEditingAllowed() {
      return this.canUpdate && !this.isEditing;
    },
    hasSavedContent() {
      return Boolean(this.savedContent);
    },
    showUpdatedAt() {
      return this.hasSavedContent && Boolean(this.updatedAt);
    },
    showGenerateMrAction() {
      return (
        !this.isEditing &&
        !this.hasContentError &&
        !this.isLoading &&
        this.hasSavedContent &&
        !this.isFlowActive &&
        this.canImplement
      );
    },
    panelHeading() {
      return s__('AgentPlan|Workplan');
    },
    // Both plan actions stay disabled for the whole run, not just the mutation: the menu
    // stays on screen throughout a regenerate because the previous plan keeps
    // `hasSavedContent` true. Regenerate would otherwise be re-offered mid-run, and a
    // delete would be silently undone when the run writes its plan back.
    areRunActionsDisabled() {
      return this.isFlowActive || this.isActionInFlight;
    },
    regenerateItem() {
      return {
        text: s__('AgentPlan|Regenerate workplan'),
        icon: 'tanuki-ai',
        extraAttrs: {
          disabled: this.areRunActionsDisabled,
          'aria-disabled': this.areRunActionsDisabled || Boolean(this.generationDisabledReason),
          class: this.generationDisabledReason ? '!gl-text-disabled' : '',
        },
        action: () => {
          if (!this.generationDisabledReason) {
            this.$emit('regenerate');
          }
        },
      };
    },
    deleteItem() {
      return {
        text: s__('AgentPlan|Delete workplan'),
        icon: 'remove',
        variant: 'danger',
        extraAttrs: { disabled: this.areRunActionsDisabled },
        action: () => {
          this.$refs.moreActions.close();
          this.$emit('delete');
        },
      };
    },
  },
  mounted() {
    document.addEventListener('keydown', this.handleKeydown);
  },
  beforeDestroy() {
    document.removeEventListener('keydown', this.handleKeydown);
  },
  methods: {
    trackImplement() {
      trackWorkplanImplement('panel', this.readinessScore);
    },
    // The view only starts editing from its empty state, through Create manually.
    onCreateManually() {
      trackWorkplanCreateManually('panel');
      this.$emit('start-edit');
    },
    handleClose() {
      const active = document.activeElement;
      const activeTag = active?.tagName;
      if (
        document.body.classList.contains('modal-open') ||
        active?.closest('.js-editor') != null ||
        activeTag === 'INPUT' ||
        activeTag === 'TEXTAREA'
      ) {
        return;
      }
      this.$emit('close');
    },
    handleKeydown({ key }) {
      if (key === 'Escape' && this.open) {
        this.handleClose();
      }
    },
  },
  WORKPLAN_GOAL_PREFIX,
  WORKPLAN_SOURCE,
  generateMrButtonOptions: { ...GENERATE_MR_BUTTON_OPTIONS, size: 'small' },
  IMPLEMENTATION_UNAVAILABLE_MESSAGE,
  IMPLEMENTATION_HELP_PATH,
};
</script>

<template>
  <mounting-portal v-if="open" mount-to="#contextual-panel-portal" append>
    <dynamic-panel
      data-testid="workplan-panel"
      :should-fill-content="isEditing"
      @close="handleClose"
    >
      <template #header>
        <div class="gl-flex gl-min-w-0 gl-items-baseline gl-gap-2">
          <span
            class="gl-shrink-0 gl-text-sm gl-font-bold gl-text-default"
            data-testid="workplan-panel-title"
          >
            {{ panelHeading }}
          </span>
          <template v-if="showUpdatedAt">
            <span class="gl-hidden gl-text-sm gl-text-subtle @sm/panel:gl-block" aria-hidden="true"
              >&middot;</span
            >
            <span
              class="gl-hidden gl-truncate gl-text-sm gl-text-subtle @sm/panel:gl-block"
              data-testid="workplan-panel-updated"
            >
              <gl-sprintf :message="s__('AgentPlan|Updated %{timeAgo}')">
                <template #timeAgo>
                  <time-ago-tooltip :time="updatedAt" />
                </template>
              </gl-sprintf>
            </span>
          </template>
        </div>
      </template>

      <template #actions>
        <duo-work-item-to-mr-action
          v-if="showGenerateMrAction"
          :project-path="fullPath"
          :work-item-iid="workItemIid"
          :work-item-type="workItemType"
          :work-item-web-url="workItemWebUrl"
          :additional-goal-context="$options.WORKPLAN_GOAL_PREFIX"
          :source="$options.WORKPLAN_SOURCE"
          :generate-mr-button-options="$options.generateMrButtonOptions"
          :disabled-flow-message="$options.IMPLEMENTATION_UNAVAILABLE_MESSAGE"
          :disabled-flow-help-path="$options.IMPLEMENTATION_HELP_PATH"
          data-testid="panel-generate-mr-with-duo"
          @triggering="trackImplement"
          @agent-flow-started="$emit('implementation-started')"
        />
        <template v-if="isEditingAllowed && hasSavedContent && !hasContentError">
          <gl-button
            v-if="!isFlowActive"
            size="small"
            category="tertiary"
            data-testid="panel-edit-button"
            @click="$emit('start-edit')"
          >
            {{ s__('AgentPlan|Edit') }}
          </gl-button>
          <gl-disclosure-dropdown
            ref="moreActions"
            v-gl-tooltip.bottom
            size="small"
            category="tertiary"
            icon="ellipsis_h"
            no-caret
            text-sr-only
            :toggle-text="__('More actions')"
            :title="__('More actions')"
            :auto-close="!generationDisabledReason"
            data-testid="panel-edit-more-actions"
          >
            <gl-disclosure-dropdown-item
              v-if="canRunWorkplan"
              ref="regenerateItem"
              :item="regenerateItem"
              :disabled="areRunActionsDisabled"
              data-testid="regenerate-workplan-item"
            />
            <gl-disclosure-dropdown-item
              :item="deleteItem"
              :disabled="areRunActionsDisabled"
              data-testid="delete-workplan-item"
            />
            <template v-if="generationDisabledReason && canRunWorkplan" #footer>
              <workplan-availability-popover
                :target="() => $refs.regenerateItem.$el"
                :reason="generationDisabledReason"
              />
            </template>
          </gl-disclosure-dropdown>
        </template>
      </template>

      <p
        v-if="showUpdatedAt"
        class="gl-mb-4 gl-text-sm gl-text-subtle @sm/panel:gl-hidden"
        data-testid="workplan-panel-updated-narrow"
      >
        <gl-sprintf :message="s__('AgentPlan|Updated %{timeAgo}')">
          <template #timeAgo>
            <time-ago-tooltip :time="updatedAt" />
          </template>
        </gl-sprintf>
      </p>
      <gl-alert
        v-if="hasContentError"
        variant="danger"
        :dismissible="false"
        :primary-button-text="s__('AgentPlan|Try again')"
        @primary-action="$emit('retry')"
      >
        {{ s__('AgentPlan|Workplan could not be loaded.') }}
      </gl-alert>
      <workplan-editor
        v-else-if="isEditing && !isLoading"
        :saved-content="savedContent"
        :draft-content="draftContent"
        :is-saving="isSaving"
        @save="$emit('save', $event)"
        @cancel-edit="$emit('cancel-edit')"
        @draft-change="$emit('draft-change', $event)"
      />
      <workplan-view
        v-else
        :is-loading="isLoading"
        :can-update="canUpdate"
        :saved-content="savedContent"
        :saved-content-html="savedContentHtml"
        :is-flow-active="isFlowActive"
        :generation-disabled-reason="generationDisabledReason"
        @start-edit="onCreateManually"
        @generate="$emit('generate')"
      />
    </dynamic-panel>
  </mounting-portal>
</template>
