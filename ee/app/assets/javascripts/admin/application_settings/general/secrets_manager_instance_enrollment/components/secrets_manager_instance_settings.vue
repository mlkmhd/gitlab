<script>
import { GlAlert, GlButton, GlLink, GlPopover, GlSprintf } from '@gitlab/ui';
import { logError } from '~/lib/logger';
import { s__ } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import SecretsManagerPaidAlert from 'ee/ci/secrets/components/secrets_manager_paid_alert.vue';
import EnableAddOnModal from 'ee/ci/secrets/components/enable_add_on_modal.vue';
import StartTrialModal from 'ee/ci/secrets/components/start_trial_modal.vue';
import { isProvisioningBlockedByEntitlement } from 'ee/ci/secrets/utils';
import getOpenbaoHealthQuery from 'ee/ci/secrets/graphql/queries/get_openbao_health.query.graphql';
import {
  CONFIGURE_OPENBAO_DOCS_LINK,
  TROUBLESHOOT_OPENBAO_DOCS_LINK,
  ENTITLEMENT_STATE_BLOCKED,
  ENTITLEMENT_STATE_OFFLINE_PAID,
  ENTITLEMENT_STATE_TRIAL_ELIGIBLE,
  I18N_SETUP_IN_PROGRESS,
  SECRETS_MANAGER_BILLING_DOCS_LINK,
} from 'ee/ci/secrets/constants';
import getInstanceEntitlementQuery from '../graphql/queries/get_instance_secrets_manager_entitlement.query.graphql';
import getInstanceSecretsManagerEnrollmentQuery from '../graphql/queries/get_instance_secrets_manager_enrollment.query.graphql';
import enableInstanceSecretsManagerAddOnMutation from '../graphql/mutations/enable_instance_secrets_manager_add_on.mutation.graphql';
import refreshInstanceSecretsManagerEntitlementMutation from '../graphql/mutations/refresh_instance_secrets_manager_entitlement.mutation.graphql';
import startInstanceSecretsManagerTrialMutation from '../graphql/mutations/start_instance_secrets_manager_trial.mutation.graphql';
import SecretsManagerInstanceEnrollmentToggle from './secrets_manager_instance_enrollment_toggle.vue';

export default {
  name: 'SecretsManagerInstanceSettings',
  components: {
    EnableAddOnModal,
    GlAlert,
    GlButton,
    GlLink,
    GlPopover,
    GlSprintf,
    SecretsManagerInstanceEnrollmentToggle,
    SecretsManagerPaidAlert,
    StartTrialModal,
  },
  I18N_SETUP_IN_PROGRESS,
  i18n: {
    loadError: s__('SecretsManager|Failed to load Secrets Manager enrollment state.'),
    enableAddOnError: s__(
      'SecretsManager|The GitLab Secrets Manager add-on could not be enabled. Please try again.',
    ),
    offlineLicenseAlert: s__(
      'SecretsManager|Contact your subscription owner to purchase a license and enable GitLab Secrets Manager.',
    ),
  },
  SECRETS_MANAGER_BILLING_DOCS_LINK,
  data() {
    return {
      entitlement: null,
      errorMessage: '',
      isCheckingEntitlement: false,
      entitlementCheckFailed: false,
      isEnablingAddOn: false,
      isEnrolled: false,
      isOpenbaoHealthy: true,
      isStartingTrial: false,
      showEnableAddOnModal: false,
      showEnrollSuccessAlert: false,
      showStartTrialModal: false,
      showTrialEnrollmentWarning: false,
    };
  },
  apollo: {
    entitlement: {
      query: getInstanceEntitlementQuery,
      context: { featureCategory: 'secrets_management' },
      update(data) {
        return data.secretsManagerInstanceEntitlement;
      },
      error(error) {
        this.reportError(error);
      },
    },
    isEnrolled: {
      query: getInstanceSecretsManagerEnrollmentQuery,
      context: { featureCategory: 'secrets_management' },
      fetchPolicy: 'network-only',
      update(data) {
        return Boolean(data?.instanceSecretsManagerEnrollment?.enrolled);
      },
      error(error) {
        this.reportError(error);
      },
    },
    isOpenbaoHealthy: {
      query: getOpenbaoHealthQuery,
      context: { featureCategory: 'secrets_management' },
      update(data) {
        return data.openbaoHealth;
      },
      error() {
        this.isOpenbaoHealthy = false;
      },
    },
  },
  computed: {
    isBlockedByEntitlement() {
      return isProvisioningBlockedByEntitlement(this.entitlement);
    },
    isEnrollmentLoading() {
      return this.$apollo.queries.isEnrolled.loading;
    },
    isOpenbaoHealthLoading() {
      return this.$apollo.queries.isOpenbaoHealthy.loading;
    },
    isOpenbaoUnavailable() {
      return this.isOpenbaoHealthLoading || !this.isOpenbaoHealthy;
    },
    // Enabling needs OpenBao; disabling (unenrollment) only writes application
    // settings, so it does not depend on OpenBao's status.
    isEnrollmentToggleDisabled() {
      return this.isBlockedByEntitlement || (this.isOpenbaoUnavailable && !this.isEnrolled);
    },
    // The toggle disables itself while loading, so waiting on the health check
    // would block unenrollment for the same reason. Enabling stays gated because
    // isEnrollmentToggleDisabled counts a pending health check as unavailable.
    isEnrollmentToggleLoading() {
      return this.isEnrollmentLoading || (this.isOpenbaoHealthLoading && !this.isEnrolled);
    },
    isOfflineLicense() {
      return this.entitlement?.offlineLicense;
    },
    showTrialNote() {
      return !this.isOfflineLicense;
    },
    // Air-gapped Flex licenses consume GitLab Credits like online ones; other offline licenses don't.
    showPaidAlert() {
      const state = this.entitlement?.state;

      if (this.isOfflineLicense) {
        return (
          state === ENTITLEMENT_STATE_OFFLINE_PAID && Boolean(this.entitlement.offlineFlexLicense)
        );
      }

      return Boolean(this.entitlement);
    },
    // A missing license is the more fundamental blocker, so surface one reason at
    // a time. The message also names setup or an outage depending on enrollment,
    // so hold it until that query settles rather than naming the wrong cause.
    showOpenbaoUnhealthyError() {
      return !this.isOpenbaoHealthy && !this.showOfflineLicenseAlert && !this.isEnrollmentLoading;
    },
    // Before enrollment the likely cause is setup; afterwards it is an
    // outage (sealed, not initialized, unreachable), so point at troubleshooting.
    openbaoUnhealthyError() {
      if (this.isEnrolled) {
        return {
          message: s__(
            'SecretsManager|Failed to connect with OpenBao. Secrets are unavailable until the connection is restored. %{linkStart}Troubleshoot OpenBao%{linkEnd}.',
          ),
          docsLink: TROUBLESHOOT_OPENBAO_DOCS_LINK,
        };
      }

      return {
        message: s__(
          'SecretsManager|Failed to connect with OpenBao. %{linkStart}Configure OpenBao%{linkEnd} before enabling GitLab Secrets Manager.',
        ),
        docsLink: CONFIGURE_OPENBAO_DOCS_LINK,
      };
    },
    showOfflineLicenseAlert() {
      return this.isOfflineLicense && this.entitlement.state === ENTITLEMENT_STATE_BLOCKED;
    },
    // Trials require CDot connectivity, so air-gapped instances keep the toggle.
    showStartTrialButton() {
      return !this.isOfflineLicense && this.entitlement?.state === ENTITLEMENT_STATE_TRIAL_ELIGIBLE;
    },
    onDemandEnabled() {
      return Boolean(this.entitlement?.onDemandEnabled);
    },
  },
  methods: {
    reportError(error, message = this.$options.i18n.loadError) {
      this.errorMessage = message;

      logError(message, error);
      Sentry.captureException(error);
    },
    onToggled(isEnrolled) {
      this.isEnrolled = isEnrolled;
      this.showEnrollSuccessAlert = isEnrolled;
      this.showTrialEnrollmentWarning = false;
    },
    async startTrial() {
      this.showStartTrialModal = false;
      this.isStartingTrial = true;
      this.errorMessage = '';

      try {
        const { data } = await this.$apollo.mutate({
          mutation: startInstanceSecretsManagerTrialMutation,
          context: { featureCategory: 'secrets_management' },
        });
        const { entitlement, errors = [] } = data?.secretsManagerInstanceStartTrial ?? {};

        // The backend auto-enrolls the instance after starting the trial. A
        // non-null entitlement means the trial started even when enrollment
        // failed; the toggle is the retry path for enrollment, so warn without
        // discarding the trial.
        if (!entitlement && errors.length) {
          throw new Error(errors.join(', '));
        }

        // A null entitlement with no errors means the trial started and the
        // instance is enrolled, but the post-trial entitlement lookup failed
        // on the backend; refetch instead of discarding the success.
        if (!entitlement) {
          this.isEnrolled = true;
          this.showEnrollSuccessAlert = true;
          await this.$apollo.queries.entitlement.refetch();
          return;
        }

        this.entitlement = entitlement;
        this.isEnrolled = errors.length === 0;
        this.showEnrollSuccessAlert = this.isEnrolled;
        this.showTrialEnrollmentWarning = !this.isEnrolled;
      } catch (error) {
        this.reportError(
          error,
          s__(
            'SecretsManager|The GitLab Secrets Manager trial could not be started. Please try again.',
          ),
        );
      } finally {
        this.isStartingTrial = false;
      }
    },
    // Consent given in the Customers Portal can be newer than the cached
    // entitlement, so re-check before showing the "no GitLab Credits" dialog.
    async openEnableAddOnModal() {
      if (this.isCheckingEntitlement) return;

      this.entitlementCheckFailed = false;

      if (!this.onDemandEnabled) {
        await this.refreshEntitlement();
      }

      this.showEnableAddOnModal = true;
    },
    async refreshEntitlement() {
      this.isCheckingEntitlement = true;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: refreshInstanceSecretsManagerEntitlementMutation,
          context: { featureCategory: 'secrets_management' },
        });
        const { entitlement } = data?.secretsManagerInstanceRefreshEntitlement ?? {};

        if (entitlement) {
          this.entitlement = entitlement;
        } else {
          this.entitlementCheckFailed = true;
        }
      } catch (error) {
        // The dialog still opens, with the entitlement the page already has and a warning.
        this.entitlementCheckFailed = true;
        Sentry.captureException(error);
      } finally {
        this.isCheckingEntitlement = false;
      }
    },
    async enableAddOn() {
      this.showEnableAddOnModal = false;
      this.isEnablingAddOn = true;
      this.errorMessage = '';

      try {
        const { data } = await this.$apollo.mutate({
          mutation: enableInstanceSecretsManagerAddOnMutation,
          context: { featureCategory: 'secrets_management' },
        });
        const { entitlement, errors = [] } = data?.secretsManagerInstanceEnableAddOn ?? {};

        // All-or-nothing: the backend enrolls and stamps the add-on intent
        // locally with a revert guard, so unlike the trial mutation there
        // is no partial-success shape to handle.
        if (!entitlement) {
          const message = errors[0] || this.$options.i18n.enableAddOnError;
          this.reportError(new Error(message), message);
          return;
        }

        this.entitlement = entitlement;
        this.isEnrolled = true;
        this.showEnrollSuccessAlert = true;
      } catch (error) {
        this.reportError(error, this.$options.i18n.enableAddOnError);
      } finally {
        this.isEnablingAddOn = false;
      }
    },
  },
};
</script>
<template>
  <div>
    <gl-alert
      v-if="errorMessage"
      class="gl-mb-4"
      variant="danger"
      data-testid="settings-error-alert"
      @dismiss="errorMessage = ''"
    >
      {{ errorMessage }}
    </gl-alert>
    <gl-alert
      v-if="showTrialEnrollmentWarning"
      class="gl-mb-4"
      variant="warning"
      data-testid="trial-enrollment-warning-alert"
      @dismiss="showTrialEnrollmentWarning = false"
    >
      {{
        s__(
          'SecretsManager|The trial has started, but the instance failed to enable the secrets manager. Please try again with the toggle below.',
        )
      }}
    </gl-alert>
    <gl-alert
      v-if="showEnrollSuccessAlert"
      class="gl-mb-4"
      variant="success"
      data-testid="enroll-success-alert"
      @dismiss="showEnrollSuccessAlert = false"
    >
      {{
        s__(
          'SecretsManager|The GitLab Secrets Manager has been enabled for all groups and projects in this instance. Visit any group or project to create secrets.',
        )
      }}
    </gl-alert>
    <template v-if="showStartTrialButton">
      <div class="gl-flex gl-items-center gl-gap-4">
        <gl-button
          ref="enableAddOnButton"
          variant="confirm"
          category="primary"
          :loading="isEnablingAddOn || isCheckingEntitlement || isOpenbaoHealthLoading"
          :disabled="isStartingTrial || isOpenbaoUnavailable"
          data-testid="instance-enable-add-on-button"
          @click="openEnableAddOnModal"
        >
          {{ s__('SecretsManager|Enable with GitLab Credits') }}
        </gl-button>
        <gl-button
          ref="startTrialButton"
          variant="confirm"
          category="secondary"
          :loading="isStartingTrial || isOpenbaoHealthLoading"
          :disabled="isEnablingAddOn || isCheckingEntitlement || isOpenbaoUnavailable"
          data-testid="instance-start-trial-button"
          @click="showStartTrialModal = true"
        >
          {{ __('Start 30-day trial') }}
        </gl-button>
        <gl-link
          :href="$options.SECRETS_MANAGER_BILLING_DOCS_LINK"
          target="_blank"
          data-testid="learn-more-trial-link"
        >
          {{ s__('SecretsManager|Learn more about the trial') }}
        </gl-link>
      </div>
      <gl-popover
        :target="() => $refs.enableAddOnButton"
        :show="isEnablingAddOn"
        :title="s__('SecretsManager|Enabling GitLab Secrets Manager')"
        placement="bottom"
        triggers="manual"
      >
        {{ $options.I18N_SETUP_IN_PROGRESS }}
      </gl-popover>
      <gl-popover
        :target="() => $refs.startTrialButton"
        :show="isStartingTrial"
        :title="s__('SecretsManager|Enabling GitLab Secrets Manager trial')"
        placement="bottom"
        triggers="manual"
      >
        {{ $options.I18N_SETUP_IN_PROGRESS }}
      </gl-popover>
      <enable-add-on-modal
        :visible="showEnableAddOnModal"
        :on-demand-enabled="onDemandEnabled"
        :entitlement-check-failed="entitlementCheckFailed"
        @enable="enableAddOn"
        @hide="showEnableAddOnModal = false"
      />
      <start-trial-modal
        :visible="showStartTrialModal"
        scope="instance"
        @start-trial="startTrial"
        @hide="showStartTrialModal = false"
      />
    </template>
    <secrets-manager-instance-enrollment-toggle
      v-else
      :is-enrolled="isEnrolled"
      :disabled="isEnrollmentToggleDisabled"
      :loading="isEnrollmentToggleLoading"
      :show-trial-note="showTrialNote"
      :is-offline-license="isOfflineLicense"
      @toggled="onToggled"
    />
    <p
      v-if="showOpenbaoUnhealthyError"
      class="gl-mb-0 gl-mt-2 gl-text-danger"
      data-testid="openbao-unhealthy-error"
    >
      <gl-sprintf :message="openbaoUnhealthyError.message">
        <template #link="{ content }">
          <gl-link :href="openbaoUnhealthyError.docsLink" target="_blank">{{ content }}</gl-link>
        </template>
      </gl-sprintf>
    </p>
    <secrets-manager-paid-alert v-if="showPaidAlert" />
    <gl-alert
      v-else-if="showOfflineLicenseAlert"
      class="gl-mt-5"
      variant="warning"
      :dismissible="false"
      data-testid="offline-license-alert"
    >
      {{ $options.i18n.offlineLicenseAlert }}
    </gl-alert>
  </div>
</template>
