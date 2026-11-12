<script>
import {
  GlMultiStepFormTemplate,
  GlButton,
  GlBadge,
  GlLink,
  GlAlert,
  GlIcon,
  GlModal,
  GlSkeletonLoader,
} from '@gitlab/ui';
import { groupBy, partition } from 'lodash-es';
import { s__ } from '~/locale';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_GROUP } from '~/graphql_shared/constants';
import { InternalEvents } from '~/tracking';
import { MAX_SELECTED_COUNT } from 'ee/security_inventory/constants';
import { isSubGroup } from 'ee/security_inventory/utils';
import securityScanProfileAttachMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_attach.mutation.graphql';
import groupAvailableSecurityScanProfilesQuery from 'ee/security_configuration/graphql/scan_profiles/group_available_security_scan_profiles.query.graphql';
import { getDefaultProfile } from 'ee/security_configuration/components/scan_profiles/utils';
import ConfirmUnsavedChangesDialog from '~/vue_shared/components/confirm_unsaved_changes_dialog.vue';
import { APPROACH_QUICK } from './constants';

export default {
  name: 'EnableScannersWizard',
  components: {
    GlMultiStepFormTemplate,
    GlButton,
    GlBadge,
    GlLink,
    GlAlert,
    GlIcon,
    GlModal,
    GlSkeletonLoader,
    ConfirmUnsavedChangesDialog,
  },
  exitModal: {
    id: 'enable-scanners-exit-modal',
    actionPrimary: {
      text: s__('SecurityConfiguration|Exit setup'),
      attributes: { variant: 'confirm' },
    },
    actionCancel: {
      text: s__('SecurityConfiguration|Continue setup'),
    },
  },
  mixins: [InternalEvents.mixin()],
  inject: ['groupFullPath', 'groupId'],
  provide() {
    return { wizard: this };
  },
  beforeRouteLeave(to, from, next) {
    if (this.confirmedExit || !this.hasUnsavedChanges) {
      next();
      return;
    }
    this.pendingRoute = to.fullPath;
    this.showExitModal = true;
    next(false);
  },
  props: {
    buildSteps: {
      type: Function,
      required: true,
    },
    profileTypes: {
      type: Array,
      required: true,
    },
    trackingEvents: {
      type: Object,
      required: true,
    },
    routes: {
      type: Object,
      required: true,
    },
    stepLabels: {
      type: Object,
      required: true,
    },
    attachModeOptions: {
      type: Array,
      required: true,
    },
    exitModalTitle: {
      type: String,
      required: false,
      default: () => s__('SecurityConfiguration|Exit scanner setup?'),
    },
  },
  apollo: {
    availableScanners: {
      query: groupAvailableSecurityScanProfilesQuery,
      variables() {
        return { fullPath: this.groupFullPath };
      },
      update(data) {
        return (data?.group?.availableSecurityScanProfiles ?? []).filter(({ scanType }) =>
          this.profileTypes.includes(scanType),
        );
      },
    },
  },
  data() {
    return {
      approach: APPROACH_QUICK,
      attachMode: (
        this.attachModeOptions.find(({ recommended }) => recommended) ?? this.attachModeOptions[0]
      )?.value,
      selectedItems: [],
      areAllItemsSelected: false,
      selectedProfiles: [],
      availableScanners: [],
      isSubmitting: false,
      submitErrors: [],
      showExitModal: false,
      confirmedExit: false,
      pendingRoute: null,
      preselectedScannerKey: this.$route?.query?.scanner ?? null,
    };
  },
  computed: {
    isLoadingAvailableScanners() {
      return this.$apollo.queries.availableScanners.loading;
    },
    profilesByScanType() {
      return groupBy(this.availableScanners, 'scanType');
    },
    allScanTypes() {
      return Object.keys(this.profilesByScanType);
    },
    currentStep() {
      return this.steps.findIndex((step) => step.route === this.$route.name);
    },
    isConfirmationRoute() {
      return this.$route.name === this.routes.confirmation;
    },
    isRouteOutsideSteps() {
      return this.currentStep === -1 && !this.isConfirmationRoute;
    },
    isReviewStep() {
      return this.$route.name === this.routes.review;
    },
    hasModeStep() {
      return this.steps.some((step) => step.route === this.routes.mode);
    },
    hasUnsavedChanges() {
      if (this.isConfirmationRoute) return false;
      if (this.$route.name === this.routes.approach && this.approach === APPROACH_QUICK)
        return false;
      return true;
    },
    steps() {
      return this.buildSteps(this);
    },
    quickSetupFirstStep() {
      return this.steps.find(
        (step) => step.route === (this.hasModeStep ? this.routes.mode : this.routes.review),
      );
    },
    previousStep() {
      const { previousRoute } = this.steps[this.currentStep] ?? {};
      if (previousRoute) {
        return this.steps.find((step) => step.route === previousRoute);
      }
      // when using the quick approach, skip back over the manual selection steps
      if (this.approach === APPROACH_QUICK && this.$route.name === this.quickSetupFirstStep.route) {
        return this.steps.find((step) => step.route === this.routes.approach);
      }
      return this.steps[this.currentStep - 1];
    },
    nextStep() {
      // when using the quick approach, skip forward over the manual selection steps
      if (this.$route.name === this.routes.approach && this.approach === APPROACH_QUICK) {
        return this.quickSetupFirstStep;
      }
      // on the final step, the "next" destination is the confirmation route
      if (this.currentStep === this.steps.length - 1) {
        return {
          route: this.routes.confirmation,
          label: s__('SecurityConfiguration|Apply configuration'),
        };
      }
      return this.steps[this.currentStep + 1];
    },
    nextLabel() {
      if (this.$route.name === this.routes.approach) {
        return this.approach === APPROACH_QUICK
          ? s__('SecurityConfiguration|Start quick setup')
          : s__('SecurityConfiguration|Start advanced setup');
      }
      return this.nextStep?.label;
    },
    currentStepLabel() {
      return this.stepLabels[this.$route.name];
    },
  },
  watch: {
    approach() {
      this.applyApproachDefaults();
    },
    availableScanners(scanners, previousScanners) {
      if (scanners.length === 0 || previousScanners.length > 0) return;

      const matchingProfile = scanners.find(
        (scanner) => scanner.scanType === this.preselectedScannerKey,
      );
      if (matchingProfile) {
        this.selectedProfiles = [matchingProfile];
        this.areAllItemsSelected = true;
      } else {
        this.applyApproachDefaults();
      }
      this.preselectedScannerKey = null;
    },
    isRouteOutsideSteps: {
      immediate: true,
      handler(isOutside) {
        if (isOutside) {
          this.$router.replace({ name: this.routes.approach });
        }
      },
    },
    currentStepLabel: {
      immediate: true,
      handler(label) {
        if (label) {
          this.trackEvent(this.trackingEvents.viewStep, { label });
        }
      },
    },
  },
  methods: {
    isStepLink(step) {
      if (this.approach === APPROACH_QUICK) {
        return [
          this.routes.approach,
          this.routes.mode,
          this.routes.capabilities,
          this.routes.review,
        ].includes(step.route);
      }
      return true;
    },
    confirmExit() {
      this.trackEvent(this.trackingEvents.abandonWizard, { label: this.currentStepLabel });
      this.confirmedExit = true;
      this.showExitModal = false;
      this.$router.push(this.pendingRoute || '/');
      this.pendingRoute = null;
    },
    keepEditing() {
      this.showExitModal = false;
      this.pendingRoute = null;
    },
    toggleItem(item, checked) {
      if (checked) {
        this.selectedItems = [...this.selectedItems, item];
        this.trackEvent(this.trackingEvents.selectItem);
      } else {
        this.selectedItems = this.selectedItems.filter(({ id }) => id !== item.id);
        this.trackEvent(this.trackingEvents.deselectItem);
      }
    },
    toggleVisibleItems(selected, visibleItems) {
      this.selectedItems = selected
        ? [...this.selectedItems, ...visibleItems].slice(0, MAX_SELECTED_COUNT)
        : this.selectedItems.filter(({ id }) => !visibleItems.some((item) => item.id === id));

      this.trackEvent(selected ? this.trackingEvents.selectItem : this.trackingEvents.deselectItem);
    },
    activeProfileForScanType(scanType) {
      return (
        this.selectedProfiles.find((scanner) => scanner.scanType === scanType) ??
        getDefaultProfile(scanType, this.profilesByScanType[scanType] ?? [])
      );
    },
    toggleScanner(scanType, checked) {
      if (checked) {
        this.selectedProfiles = [...this.selectedProfiles, this.activeProfileForScanType(scanType)];
        this.trackEvent(this.trackingEvents.selectScanner, { label: scanType });
      } else {
        this.selectedProfiles = this.selectedProfiles.filter(
          (scanner) => scanner.scanType !== scanType,
        );
        this.trackEvent(this.trackingEvents.deselectScanner, { label: scanType });
      }
    },
    selectScannerProfile(scanType, newProfile) {
      this.selectedProfiles = [
        ...this.selectedProfiles.filter((scanner) => scanner.scanType !== scanType),
        newProfile,
      ];
    },
    toggleAllScanners(checked) {
      const previouslySelectedTypes = this.selectedProfiles.map(({ scanType }) => scanType);
      this.selectedProfiles = checked
        ? this.allScanTypes.map((scanType) => this.activeProfileForScanType(scanType))
        : [];

      const event = checked
        ? this.trackingEvents.selectScanner
        : this.trackingEvents.deselectScanner;
      const affectedTypes = checked
        ? this.allScanTypes.filter((scanType) => !previouslySelectedTypes.includes(scanType))
        : previouslySelectedTypes;
      affectedTypes.forEach((label) => this.trackEvent(event, { label }));
    },
    applyApproachDefaults() {
      const isQuick = this.approach === APPROACH_QUICK;
      // Set selectedProfiles directly rather than via toggleAllScanners so the
      // implicit quick-setup selection doesn't emit per-scanner select events.
      this.selectedProfiles = isQuick
        ? this.allScanTypes.map((scanType) => this.activeProfileForScanType(scanType))
        : [];
      this.areAllItemsSelected = isQuick;
    },
    goToNextStep() {
      if (this.$route.name === this.routes.approach) {
        this.trackEvent(this.trackingEvents.startWizard, { label: this.approach });
      }

      this.$router.push({ name: this.nextStep.route });
    },
    async onSubmit() {
      this.isSubmitting = true;
      this.submitErrors = [];

      let projectIds = [];
      let groupIds = [];
      if (this.areAllItemsSelected) {
        groupIds = [convertToGraphQLId(TYPENAME_GROUP, this.groupId)];
      } else {
        [groupIds, projectIds] = partition(this.selectedItems, isSubGroup).map((items) =>
          items.map(({ id }) => id),
        );
      }

      try {
        const results = await Promise.all(
          this.selectedProfiles.map((scanner) =>
            this.$apollo.mutate({
              mutation: securityScanProfileAttachMutation,
              variables: {
                input: {
                  securityScanProfileId: scanner.id,
                  projectIds,
                  groupIds,
                  ...(this.hasModeStep && { mode: this.attachMode }),
                },
              },
            }),
          ),
        );

        this.submitErrors = results.flatMap(
          ({ data }) => data?.securityScanProfileAttach?.errors ?? [],
        );

        if (this.submitErrors.length === 0) {
          this.trackEvent(this.trackingEvents.applyWizard, {
            label: this.approach,
            ...(this.hasModeStep && { property: this.attachMode }),
          });
          this.$router.push({ name: this.routes.confirmation });
        }
      } catch (e) {
        this.submitErrors = [e.message];
      } finally {
        this.isSubmitting = false;
      }
    },
  },
};
</script>
<template>
  <div>
    <confirm-unsaved-changes-dialog :has-unsaved-changes="hasUnsavedChanges" />
    <router-view v-if="isConfirmationRoute" />
    <template v-else>
      <gl-alert v-if="submitErrors.length" variant="danger" class="gl-mt-4" :dismissible="false">
        <ul class="gl-m-0 gl-pl-4">
          <li v-for="error in submitErrors" :key="error">{{ error }}</li>
        </ul>
      </gl-alert>
      <div class="gl-flex gl-justify-center gl-gap-4 gl-pt-5">
        <component
          :is="isStepLink(step) ? 'gl-link' : 'span'"
          v-for="(step, i) in steps"
          :key="i"
          :to="isStepLink(step) ? { name: step.route } : null"
          class="gl-cursor-default gl-rounded-full gl-bg-strong gl-px-5 gl-py-3 gl-text-default gl-no-underline hover:gl-text-default hover:gl-no-underline"
          :class="{ 'gl-bg-transparent': currentStep !== i }"
          data-testid="wizard-step"
        >
          <gl-icon
            v-if="currentStep > i"
            name="check-circle-filled"
            class="gl-mr-2 gl-h-5 gl-w-5 gl-fill-feedback-success"
          />
          <gl-badge
            v-else
            class="gl-mr-2 gl-h-5 gl-w-5 gl-rounded-full"
            :class="{
              '!gl-bg-neutral-700 !gl-text-feedback-strong': currentStep === i,
            }"
            >{{ i + 1 }}
          </gl-badge>
          {{ step.label }}
          <gl-badge v-if="currentStep > i && step.count">{{ step.count }}</gl-badge>
        </component>
      </div>
      <gl-multi-step-form-template
        :title="steps[currentStep]?.label"
        :current-step="currentStep + 1"
        :steps-total="steps.length"
        class="gl-mb-5 gl-max-w-full"
      >
        <template #default>
          <div
            v-if="isLoadingAvailableScanners"
            data-testid="wizard-content-loading-skeleton"
            class="gl-flex gl-flex-col gl-gap-4"
          >
            <gl-skeleton-loader :width="800" :height="20">
              <rect x="0" y="0" width="240" height="20" rx="4" />
            </gl-skeleton-loader>
            <gl-skeleton-loader :width="800" :height="60">
              <rect x="0" y="0" width="800" height="60" rx="6" />
            </gl-skeleton-loader>
            <gl-skeleton-loader :width="800" :height="60">
              <rect x="0" y="0" width="800" height="60" rx="6" />
            </gl-skeleton-loader>
          </div>
          <router-view v-else v-bind="steps[currentStep]?.props" />
        </template>
      </gl-multi-step-form-template>
      <div class="settings-sticky-footer gl-flex gl-justify-between">
        <gl-button to="/" data-testid="cancel-button">{{ __('Cancel') }}</gl-button>
        <span>
          <gl-button
            v-if="previousStep"
            :to="{ name: previousStep.route }"
            data-testid="back-button"
          >
            <gl-icon name="chevron-left" class="gl-mr-2" />{{ previousStep.label }}
          </gl-button>
          <gl-button
            v-if="isReviewStep"
            category="primary"
            variant="confirm"
            :loading="isSubmitting"
            data-testid="next-button"
            @click="onSubmit"
          >
            {{ nextLabel }}<gl-icon name="chevron-right" class="gl-ml-2" />
          </gl-button>
          <gl-button
            v-else-if="nextStep"
            category="primary"
            variant="confirm"
            data-testid="next-button"
            @click="goToNextStep"
          >
            {{ nextLabel }}<gl-icon name="chevron-right" class="gl-ml-2" />
          </gl-button>
        </span>
      </div>
      <gl-modal
        v-model="showExitModal"
        :modal-id="$options.exitModal.id"
        size="sm"
        :title="exitModalTitle"
        :action-primary="$options.exitModal.actionPrimary"
        :action-cancel="$options.exitModal.actionCancel"
        data-testid="exit-confirmation-modal"
        @primary="confirmExit"
        @canceled="keepEditing"
        @hidden="keepEditing"
      >
        {{
          s__(
            "SecurityConfiguration|Your progress won't be saved. You'll need to start over if you return.",
          )
        }}
      </gl-modal>
    </template>
  </div>
</template>
