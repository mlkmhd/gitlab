<script>
import { GlToggle, GlLink, GlSprintf, GlProgressBar } from '@gitlab/ui';
import DuoReadinessAgentConfigRow from 'ee_component/ai/settings/readiness/components/duo_readiness_agent_config_row.vue';
import DuoReadinessPlatformRow from 'ee_component/ai/settings/readiness/components/duo_readiness_platform_row.vue';
import DuoReadinessRunnerRow from 'ee_component/ai/settings/readiness/components/duo_readiness_runner_row.vue';
import DuoReadinessOrbitRow from 'ee_component/ai/settings/readiness/components/duo_readiness_orbit_row.vue';
import DuoReadinessMcpRow from 'ee_component/ai/settings/readiness/components/duo_readiness_mcp_row.vue';
import DuoReadinessInheritedList from 'ee_component/ai/settings/readiness/components/duo_readiness_inherited_list.vue';
import CascadingLockIcon from '~/namespaces/cascading_settings/components/cascading_lock_icon.vue';
import { n__, s__, sprintf } from '~/locale';
import { duoFlowHelpPath } from '~/ai/constants';
import { STATUS_DONE, STATUS_TODO, STATUS_BLOCKED, STATUS_LOADING } from '../constants';
import DuoReadinessRow from './duo_readiness_row.vue';
import DuoLocalSetupSection from './duo_local_setup_section.vue';

const REQUIRED_STEP_COUNT = 4;

export default {
  name: 'DuoReadinessCard',
  components: {
    GlToggle,
    GlLink,
    GlSprintf,
    GlProgressBar,
    CascadingLockIcon,
    DuoReadinessRow,
    DuoReadinessPlatformRow,
    DuoReadinessRunnerRow,
    DuoReadinessAgentConfigRow,
    DuoReadinessOrbitRow,
    DuoReadinessMcpRow,
    DuoReadinessInheritedList,
    DuoLocalSetupSection,
  },
  props: {
    duoEnabledSetting: {
      type: Object,
      required: true,
    },
    duoReadiness: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    duoOrbit: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    duoMcp: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    projectFullPath: {
      type: String,
      required: false,
      default: '',
    },
    duoFeaturesLocked: {
      type: Boolean,
      required: false,
      default: false,
    },
    duoAvailabilityCascadingSettings: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    duoRemoteFlowsCascadingSettings: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    duoFoundationalFlowsCascadingSettings: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    duoScheduledTriggersCascadingSettings: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    duoEnabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    duoRemoteFlowsAvailability: {
      type: Boolean,
      required: false,
      default: false,
    },
    duoFoundationalFlowsAvailability: {
      type: Boolean,
      required: false,
      default: false,
    },
    duoScheduledTriggersAvailability: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  emits: [
    'update:duo-enabled',
    'update:duo-remote-flows-availability',
    'update:duo-foundational-flows-availability',
    'update:duo-scheduled-triggers-availability',
  ],
  data() {
    return {
      runnerStatus: STATUS_LOADING,
    };
  },
  computed: {
    platformEnabled() {
      return Boolean(this.duoReadiness.platformEnabled);
    },
    showAvailabilityCascadingButton() {
      return (
        this.duoFeaturesLocked &&
        this.duoAvailabilityCascadingSettings &&
        Object.keys(this.duoAvailabilityCascadingSettings).length
      );
    },
    showRemoteFlowsCascadingLock() {
      return (
        this.duoRemoteFlowsCascadingSettings?.lockedByAncestor ||
        this.duoRemoteFlowsCascadingSettings?.lockedByApplicationSetting
      );
    },
    areFoundationalFlowsLocked() {
      return (
        this.duoFoundationalFlowsCascadingSettings?.lockedByAncestor ||
        this.duoFoundationalFlowsCascadingSettings?.lockedByApplicationSetting
      );
    },
    duoRowStatus() {
      return this.duoEnabled ? STATUS_DONE : STATUS_TODO;
    },
    flowExecutionRowStatus() {
      if (!this.platformEnabled || !this.duoEnabled) return STATUS_BLOCKED;

      return this.duoRemoteFlowsAvailability ? STATUS_DONE : STATUS_TODO;
    },
    foundationalFlowsRowStatus() {
      if (!this.effectiveFlowExecutionEnabled) return STATUS_BLOCKED;

      return this.duoFoundationalFlowsAvailability ? STATUS_DONE : STATUS_TODO;
    },
    scheduledTriggersRowStatus() {
      if (!this.effectiveFlowExecutionEnabled) return STATUS_BLOCKED;

      return this.duoScheduledTriggersAvailability ? STATUS_DONE : STATUS_TODO;
    },
    areScheduledTriggersLocked() {
      return (
        this.duoScheduledTriggersCascadingSettings?.lockedByAncestor ||
        this.duoScheduledTriggersCascadingSettings?.lockedByApplicationSetting
      );
    },
    effectiveFlowExecutionEnabled() {
      return this.platformEnabled && this.duoEnabled && this.duoRemoteFlowsAvailability;
    },
    inheritedFlows() {
      return this.duoReadiness.foundationalFlows ?? [];
    },
    // Null when no top-level group reports agents to this project; an empty list means it turned none on.
    showInheritedAgentsRow() {
      return Boolean(this.duoReadiness.foundationalAgents);
    },
    inheritedAgents() {
      return this.duoReadiness.foundationalAgents ?? [];
    },
    inheritedAgentsDescription() {
      return this.inheritedAgents.length
        ? s__(
            'DuoAgentPlatform|This project can use these agents built and maintained by GitLab. Set by %{group}.',
          )
        : s__('DuoAgentPlatform|No foundational agents are turned on by %{group}.');
    },
    // Agents run in the project only while the Agent Platform and GitLab Duo are on for it.
    agentsUsable() {
      return this.platformEnabled && this.duoEnabled;
    },
    showOrbitRow() {
      return Boolean(this.duoOrbit.rootGroupPath);
    },
    showMcpRow() {
      return Boolean(this.duoMcp.serversPath);
    },
    showRecommendedGroup() {
      return this.platformEnabled;
    },
    doneCount() {
      return [
        this.platformEnabled,
        this.duoRowStatus === STATUS_DONE,
        this.flowExecutionRowStatus === STATUS_DONE,
        this.runnerStatus === STATUS_DONE,
      ].filter(Boolean).length;
    },
    stepsLeft() {
      return REQUIRED_STEP_COUNT - this.doneCount;
    },
    allStepsComplete() {
      return this.stepsLeft === 0;
    },
    progressCountText() {
      if (this.allStepsComplete) return this.$options.i18n.allStepsComplete;

      return n__('DuoAgentPlatform|%d step left', 'DuoAgentPlatform|%d steps left', this.stepsLeft);
    },
    progressBarLabel() {
      return sprintf(this.$options.i18n.progressBarLabel, {
        done: this.doneCount,
        total: REQUIRED_STEP_COUNT,
      });
    },
    requiredSubtitle() {
      return sprintf(this.$options.i18n.requiredSubtitle, { count: REQUIRED_STEP_COUNT });
    },
    stateLine() {
      if (!this.platformEnabled) return this.$options.i18n.stateBlocked;
      if (this.allStepsComplete) return this.$options.i18n.stateReady;
      if (this.duoRowStatus !== STATUS_DONE) return this.$options.i18n.stateNotSetUp;
      if (this.flowExecutionRowStatus !== STATUS_DONE) {
        return n__(
          'DuoAgentPlatform|Chat and Code Suggestions work today. %d more step to set up flows.',
          'DuoAgentPlatform|Chat and Code Suggestions work today. %d more steps to set up flows.',
          this.stepsLeft,
        );
      }

      return n__(
        'DuoAgentPlatform|%d step left to set up flows.',
        'DuoAgentPlatform|%d steps left to set up flows.',
        this.stepsLeft,
      );
    },
  },
  duoFlowHelpPath,
  REQUIRED_STEP_COUNT,
  i18n: {
    readinessHeading: s__('DuoAgentPlatform|Run GitLab Duo agents and flows in this project'),
    requiredHeading: s__('DuoAgentPlatform|Required'),
    requiredSubtitle: s__(
      'DuoAgentPlatform|All %{count} are required for full agent and flow support.',
    ),
    recommendedHeading: s__('DuoAgentPlatform|Recommended'),
    recommendedSubtitle: s__(
      'DuoAgentPlatform|Flows run without these. Set them up for the best results.',
    ),
    allStepsComplete: s__('DuoAgentPlatform|All steps complete'),
    progressBarLabel: s__(
      'DuoAgentPlatform|Agent setup progress: %{done} of %{total} steps complete',
    ),
    duoRowDescription: s__('DuoAgentPlatform|Turn on AI-native features for this project.'),
    flowExecutionTitle: s__('DuoAgentPlatform|Flow execution'),
    flowExecutionDescription: s__(
      'DuoAgentPlatform|Turn on flows so agents can review merge requests, fix pipelines, and more.',
    ),
    foundationalFlowsDescription: s__(
      'DuoAgentPlatform|Production-ready flows built and maintained by GitLab.',
    ),
    foundationalFlowsInheritedDescription: s__(
      'DuoAgentPlatform|Production-ready flows built and maintained by GitLab. Set by %{group}.',
    ),
    stateNotSetUp: s__('DuoAgentPlatform|Not set up yet. To get started, turn on GitLab Duo.'),
    stateReady: s__('DuoAgentPlatform|Ready. Flows can run in this project.'),
    stateBlocked: s__(
      'DuoAgentPlatform|Blocked: the Agent Platform is off, so nothing below can be set up yet.',
    ),
  },
};
</script>

<template>
  <div class="gl-mb-6" data-testid="duo-readiness-block">
    <div class="gl-mb-4 gl-flex gl-items-start gl-justify-between gl-gap-5">
      <div class="gl-min-w-0">
        <h3 class="gl-heading-3 gl-mb-2" data-testid="readiness-heading">
          {{ $options.i18n.readinessHeading }}
        </h3>
        <p class="gl-mb-0 gl-text-sm gl-text-subtle" data-testid="readiness-state-line">
          {{ stateLine }}
        </p>
      </div>
      <div class="gl-w-1/4 gl-shrink-0 gl-text-right">
        <span class="gl-text-sm gl-text-subtle" data-testid="readiness-progress-count">
          {{ progressCountText }}
        </span>
        <gl-progress-bar
          :value="doneCount"
          :max="$options.REQUIRED_STEP_COUNT"
          :aria-label="progressBarLabel"
          :variant="allStepsComplete ? 'success' : 'primary'"
          class="gl-mt-2"
          data-testid="readiness-progress-bar"
        />
      </div>
    </div>

    <div class="gl-mb-3 gl-flex gl-flex-wrap gl-items-baseline gl-gap-3">
      <span class="gl-font-bold">{{ $options.i18n.requiredHeading }}</span>
      <span class="gl-text-sm gl-text-subtle">{{ requiredSubtitle }}</span>
    </div>

    <div class="gl-border gl-overflow-hidden gl-rounded-lg">
      <duo-readiness-platform-row :readiness="duoReadiness" />

      <duo-readiness-row
        :title="duoEnabledSetting.label"
        :status="duoRowStatus"
        data-testid="duo-row"
      >
        <template #description>
          {{ $options.i18n.duoRowDescription }}
          <gl-link
            :href="duoEnabledSetting.helpPath"
            target="_blank"
            data-testid="duo-row-help-link"
            >{{ __('Learn more') }}</gl-link
          >
        </template>
        <template #title-icon>
          <cascading-lock-icon
            v-if="showAvailabilityCascadingButton"
            data-testid="duo-cascading-lock-icon"
            :is-locked-by-group-ancestor="duoAvailabilityCascadingSettings.lockedByAncestor"
            :is-locked-by-application-settings="
              duoAvailabilityCascadingSettings.lockedByApplicationSetting
            "
            :ancestor-namespace="duoAvailabilityCascadingSettings.ancestorNamespace"
            class="gl-ml-1"
          />
        </template>
        <gl-toggle
          :value="duoEnabled"
          :disabled="duoFeaturesLocked"
          :label="duoEnabledSetting.label"
          label-position="hidden"
          name="project[project_setting_attributes][duo_features_enabled]"
          data-testid="duo_features_enabled_toggle"
          @change="$emit('update:duo-enabled', $event)"
        />
      </duo-readiness-row>

      <!-- The top-level group picks the agents, so this row only reports them: no status, no control. -->
      <duo-readiness-row
        v-if="showInheritedAgentsRow"
        nested
        :disabled="!agentsUsable"
        :title="s__('DuoAgentPlatform|Foundational agents')"
        data-testid="foundational-agents-row"
      >
        <template #description>
          <gl-sprintf :message="inheritedAgentsDescription">
            <template #group>
              <gl-link
                v-if="duoReadiness.groupSettingsPath"
                :href="duoReadiness.groupSettingsPath"
                data-testid="foundational-agents-group-link"
                >{{ duoReadiness.rootGroupName }}</gl-link
              >
              <template v-else>{{ duoReadiness.rootGroupName }}</template>
            </template>
          </gl-sprintf>
        </template>
      </duo-readiness-row>
      <duo-readiness-inherited-list
        v-if="inheritedAgents.length"
        :items="inheritedAgents"
        :disabled="!agentsUsable"
        data-testid="foundational-agent-list-row"
      />

      <duo-readiness-row
        :title="$options.i18n.flowExecutionTitle"
        :status="flowExecutionRowStatus"
        data-testid="flow-execution-row"
      >
        <template #title-icon>
          <cascading-lock-icon
            v-if="showRemoteFlowsCascadingLock"
            data-testid="duo-flows-cascading-lock-icon"
            :is-locked-by-group-ancestor="duoRemoteFlowsCascadingSettings.lockedByAncestor"
            :is-locked-by-application-settings="
              duoRemoteFlowsCascadingSettings.lockedByApplicationSetting
            "
            :ancestor-namespace="duoRemoteFlowsCascadingSettings.ancestorNamespace"
            class="gl-ml-1"
          />
        </template>
        <template #description>
          {{ $options.i18n.flowExecutionDescription }}
          <gl-sprintf :message="s__('DuoAgentPlatform|%{linkStart}What are flows?%{linkEnd}')">
            <template #link="{ content }">
              <gl-link :href="$options.duoFlowHelpPath" target="_blank">{{ content }}</gl-link>
            </template>
          </gl-sprintf>
        </template>
        <gl-toggle
          :value="duoRemoteFlowsAvailability"
          :disabled="!platformEnabled || !duoEnabled || showRemoteFlowsCascadingLock"
          :label="s__('DuoAgentPlatform|Remote GitLab Duo Flows')"
          label-position="hidden"
          name="project[project_setting_attributes][duo_remote_flows_enabled]"
          data-testid="duo-remote-flows-enabled"
          @change="$emit('update:duo-remote-flows-availability', $event)"
        />
      </duo-readiness-row>

      <duo-readiness-row
        nested
        :title="s__('DuoAgentPlatform|Allow foundational flows')"
        :status="foundationalFlowsRowStatus"
        data-testid="foundational-flows-row"
      >
        <template #description>
          <gl-sprintf
            v-if="inheritedFlows.length"
            :message="$options.i18n.foundationalFlowsInheritedDescription"
          >
            <template #group>
              <gl-link
                v-if="duoReadiness.groupSettingsPath"
                :href="duoReadiness.groupSettingsPath"
                data-testid="foundational-flows-group-link"
                >{{ duoReadiness.rootGroupName }}</gl-link
              >
              <template v-else>{{ duoReadiness.rootGroupName }}</template>
            </template>
          </gl-sprintf>
          <template v-else>{{ $options.i18n.foundationalFlowsDescription }}</template>
        </template>
        <template #title-icon>
          <cascading-lock-icon
            v-if="areFoundationalFlowsLocked"
            data-testid="duo-foundational-flows-cascading-lock-icon"
            :is-locked-by-group-ancestor="duoFoundationalFlowsCascadingSettings.lockedByAncestor"
            :is-locked-by-application-settings="
              duoFoundationalFlowsCascadingSettings.lockedByApplicationSetting
            "
            :ancestor-namespace="duoFoundationalFlowsCascadingSettings.ancestorNamespace"
            class="gl-ml-1"
          />
        </template>
        <gl-toggle
          :value="duoFoundationalFlowsAvailability"
          :disabled="
            !platformEnabled ||
            !duoEnabled ||
            !duoRemoteFlowsAvailability ||
            areFoundationalFlowsLocked
          "
          :label="s__('DuoAgentPlatform|Foundational GitLab Duo Flows')"
          label-position="hidden"
          name="project[project_setting_attributes][duo_foundational_flows_enabled]"
          data-testid="duo-foundational-flows-enabled"
          @change="$emit('update:duo-foundational-flows-availability', $event)"
        />
        <template v-if="inheritedFlows.length" #body>
          <ul
            class="gl-m-0 gl-ml-5 gl-list-none gl-p-0"
            :class="{ 'gl-text-disabled': !effectiveFlowExecutionEnabled }"
            data-testid="foundational-flow-list"
          >
            <li v-for="flow in inheritedFlows" :key="flow.reference" class="gl-py-1">
              {{ flow.name }}
            </li>
          </ul>
        </template>
      </duo-readiness-row>

      <duo-readiness-row
        nested
        :title="s__('DuoAgentPlatform|Allow scheduled automations')"
        :description="
          s__(
            'DuoAgentPlatform|Let flows run on a schedule. Turning this off keeps existing schedules but stops them from running, and does not cancel runs already in progress.',
          )
        "
        :status="scheduledTriggersRowStatus"
        data-testid="scheduled-triggers-row"
      >
        <template #title-icon>
          <cascading-lock-icon
            v-if="areScheduledTriggersLocked"
            data-testid="duo-scheduled-triggers-cascading-lock-icon"
            :is-locked-by-group-ancestor="duoScheduledTriggersCascadingSettings.lockedByAncestor"
            :is-locked-by-application-settings="
              duoScheduledTriggersCascadingSettings.lockedByApplicationSetting
            "
            :ancestor-namespace="duoScheduledTriggersCascadingSettings.ancestorNamespace"
            class="gl-ml-1"
          />
        </template>
        <gl-toggle
          :value="duoScheduledTriggersAvailability"
          :disabled="!effectiveFlowExecutionEnabled || areScheduledTriggersLocked"
          :label="s__('DuoAgentPlatform|Scheduled automations')"
          label-position="hidden"
          name="project[project_setting_attributes][duo_scheduled_triggers_enabled]"
          data-testid="duo-scheduled-triggers-enabled"
          @change="$emit('update:duo-scheduled-triggers-availability', $event)"
        />
      </duo-readiness-row>

      <duo-readiness-runner-row
        :readiness="duoReadiness"
        :flow-execution-enabled="effectiveFlowExecutionEnabled"
        :project-full-path="projectFullPath"
        @status-changed="runnerStatus = $event"
      />
    </div>

    <div v-if="showRecommendedGroup" class="gl-mt-5" data-testid="duo-recommended-group">
      <div class="gl-mb-3 gl-flex gl-flex-wrap gl-items-baseline gl-gap-3">
        <span class="gl-font-bold">{{ $options.i18n.recommendedHeading }}</span>
        <span class="gl-text-sm gl-text-subtle">{{ $options.i18n.recommendedSubtitle }}</span>
      </div>
      <div class="gl-border gl-overflow-hidden gl-rounded-lg">
        <duo-readiness-agent-config-row
          :readiness="duoReadiness"
          :flow-execution-enabled="effectiveFlowExecutionEnabled"
          :project-full-path="projectFullPath"
        />
        <duo-readiness-orbit-row
          v-if="showOrbitRow"
          :orbit="duoOrbit"
          :full-path="projectFullPath"
        />
        <duo-readiness-mcp-row
          v-if="showMcpRow"
          :mcp="duoMcp"
          :project-full-path="projectFullPath"
        />
      </div>
    </div>

    <duo-local-setup-section class="gl-mt-5" />
  </div>
</template>
