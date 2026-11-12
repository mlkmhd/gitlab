<script>
import { GlAlert, GlButton, GlToastMixin, GlTooltipDirective } from '@gitlab/ui';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_action';
import { __, s__, sprintf } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION } from '~/security_configuration/constants';
import glFeatureFlagMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import SectionLoader from '~/vue_shared/security_configuration/components/section_loader.vue';
import projectProfilesQuery from 'ee/security_configuration/graphql/scan_profiles/project_security_scan_profiles.query.graphql';
import detachMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_detach.mutation.graphql';
import AutoRemediationCapabilities from './auto_remediation_capabilities.vue';
import AutoRemediationCard from './auto_remediation_card.vue';
import TriageProfileDrawer from './triage_profile_drawer.vue';

export default {
  name: 'AutoRemediationSectionEE',
  i18n: {
    removeProfile: s__('SecurityConfiguration|Remove profile'),
  },
  components: {
    AutoRemediationCapabilities,
    AutoRemediationCard,
    GlAlert,
    GlButton,
    SectionLoader,
    TriageProfileDrawer,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [GlToastMixin, glFeatureFlagMixin()],
  inject: ['projectFullPath', 'canApplyProfiles', 'securityScanProfilesLicensed'],
  data() {
    return {
      hasError: false,
      isDetailsOpen: false,
      isDrawerOpen: false,
      isRemoving: false,
      project: null,
      removeError: '',
    };
  },
  apollo: {
    project: {
      skip() {
        return !this.isAvailable;
      },
      query: projectProfilesQuery,
      variables() {
        return { fullPath: this.projectFullPath };
      },
      result({ error }) {
        if (!error) this.hasError = false;
      },
      error(error) {
        this.hasError = true;
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    attachedProfile() {
      return (
        this.project?.securityScanProfiles?.find(
          ({ scanType }) => scanType === SCAN_PROFILE_TYPE_TRIAGE_AND_REMEDIATION,
        ) ?? null
      );
    },
    capabilities() {
      return this.project?.triageAndRemediationCoverage?.capabilities ?? [];
    },
    isAvailable() {
      return Boolean(
        this.glFeatures.triageAndRemediationProfilesUi && this.securityScanProfilesLicensed,
      );
    },
    isLoading() {
      return this.$apollo.queries.project.loading;
    },
  },
  methods: {
    openDrawer() {
      this.isDrawerOpen = true;
    },
    closeDrawer() {
      this.isDrawerOpen = false;
    },
    openDetails() {
      this.isDetailsOpen = true;
    },
    async closeDetails() {
      this.isDetailsOpen = false;
      await this.$nextTick();
      this.$refs.card?.focusProfileLink();
    },
    refetchProject() {
      return this.$apollo.queries.project.refetch();
    },
    confirmRemoval() {
      return confirmAction(
        s__(
          'SecurityConfiguration|Automated Triage and Remediation stops acting on vulnerabilities in this project. Merge requests it already opened stay open.',
        ),
        {
          title: sprintf(s__('SecurityConfiguration|Remove %{profileName} from %{projectName}?'), {
            profileName: this.attachedProfile.name,
            projectName: this.project.name,
          }),
          primaryBtnText: this.$options.i18n.removeProfile,
          primaryBtnVariant: 'danger',
          cancelBtnText: __('Cancel'),
        },
      );
    },
    async removeProfile() {
      if (!(await this.confirmRemoval())) return;

      const { name: profileName } = this.attachedProfile;
      const { name: projectName } = this.project;
      this.isRemoving = true;
      this.removeError = '';

      try {
        const { data } = await this.$apollo.mutate({
          mutation: detachMutation,
          variables: {
            input: {
              securityScanProfileId: this.attachedProfile.id,
              projectIds: [this.project.id],
            },
          },
          refetchQueries: [
            { query: projectProfilesQuery, variables: { fullPath: this.projectFullPath } },
          ],
          awaitRefetchQueries: true,
        });

        const { errors } = data.securityScanProfileDetach;
        if (errors.length) {
          this.removeError = errors.join(', ');
        } else {
          this.$toast.show(
            sprintf(s__('SecurityConfiguration|%{profileName} removed from %{projectName}.'), {
              profileName,
              projectName,
            }),
          );
        }
      } catch (error) {
        this.removeError = s__('SecurityConfiguration|Failed to remove the profile.');
        Sentry.captureException(error);
      } finally {
        this.isRemoving = false;
      }
    },
  },
};
</script>

<template>
  <div v-if="isAvailable" class="gl-pt-5" data-testid="auto-remediation-section">
    <div v-if="attachedProfile" class="gl-mb-5 gl-flex gl-items-start gl-justify-between gl-gap-5">
      <div>
        <h2 class="gl-mb-3 gl-mt-0 gl-text-size-h2">
          {{ s__('SecurityConfiguration|Automated Triage and Remediation') }}
        </h2>
        <p class="gl-mb-0" data-testid="auto-remediation-description">
          {{
            s__(
              'SecurityConfiguration|Define how GitLab triages and fixes vulnerabilities in this project.',
            )
          }}
        </p>
      </div>
      <div v-if="canApplyProfiles" class="gl-flex gl-shrink-0 gl-gap-3">
        <gl-button
          :disabled="isRemoving"
          data-testid="auto-remediation-change-button"
          @click="openDrawer"
        >
          {{ s__('SecurityConfiguration|Change profile') }}
        </gl-button>
        <gl-button
          v-gl-tooltip
          icon="remove"
          :title="$options.i18n.removeProfile"
          :aria-label="$options.i18n.removeProfile"
          :loading="isRemoving"
          data-testid="auto-remediation-remove-button"
          @click="removeProfile"
        />
      </div>
    </div>
    <gl-alert
      v-if="removeError"
      class="gl-mb-4"
      variant="danger"
      data-testid="auto-remediation-remove-error"
      @dismiss="removeError = ''"
    >
      {{ removeError }}
    </gl-alert>
    <section-loader v-if="isLoading" />
    <gl-alert
      v-else-if="hasError"
      variant="danger"
      :dismissible="false"
      data-testid="auto-remediation-error"
    >
      {{ s__('SecurityConfiguration|Failed to load triage and remediation profiles.') }}
    </gl-alert>
    <auto-remediation-card
      v-else
      ref="card"
      :profile="attachedProfile"
      :can-apply-profiles="canApplyProfiles"
      @select-profile="openDrawer"
      @view-profile="openDetails"
    />
    <auto-remediation-capabilities
      v-if="attachedProfile && !isLoading && !hasError"
      :profile="attachedProfile"
      :capabilities="capabilities"
    />
    <triage-profile-drawer
      :open="isDetailsOpen"
      :project="project"
      :preset-id="attachedProfile ? attachedProfile.id : ''"
      :profile="attachedProfile"
      details-only
      @close="closeDetails"
    />
    <triage-profile-drawer
      :open="isDrawerOpen"
      :project="project"
      :preset-id="attachedProfile ? attachedProfile.id : ''"
      @close="closeDrawer"
      @applied="refetchProject"
    />
  </div>
</template>
