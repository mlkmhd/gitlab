<script>
import {
  GlBadge,
  GlButton,
  GlEmptyState,
  GlTab,
  GlTabs,
  GlToastMixin,
  GlTooltipDirective,
} from '@gitlab/ui';
import EMPTY_STATE_SVG from '@gitlab/svgs/dist/illustrations/empty-state/empty-secure-md.svg?url';
import { createAlert } from '~/alert';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal';
import { n__, s__, sprintf } from '~/locale';
import { SCAN_PROFILE_I18N } from '~/security_configuration/constants';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import groupAvailableSecurityScanProfilesQuery from 'ee/security_configuration/graphql/scan_profiles/group_available_security_scan_profiles.query.graphql';
import attachMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_attach.mutation.graphql';
import ProfileListDrawer from './profile_list_drawer.vue';
import TriagePresetCapabilities from './triage_preset_capabilities.vue';
import { getTriagePresets, scanTypeName, managedByLabel, selectionLabel } from './utils';

const FLASH_CONTAINER_CLASS = 'js-triage-profile-drawer-flash-container';
const STANDARD_TRIAGE_PRESET_NAME = 'Triage and Remediation (Standard)';

const i18n = {
  generalDetails: s__('ScanProfiles|General details'),
  description: s__('ScanProfiles|Description'),
  profileType: s__('ScanProfiles|Profile type'),
  managedBy: s__('ScanProfiles|Managed by'),
};

export default {
  name: 'TriageProfileDrawer',
  components: {
    CrudComponent,
    GlBadge,
    GlButton,
    GlEmptyState,
    GlTab,
    GlTabs,
    ProfileListDrawer,
    TriagePresetCapabilities,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [GlToastMixin],
  inject: ['groupFullPath'],
  props: {
    open: {
      type: Boolean,
      required: false,
      default: false,
    },
    project: {
      type: Object,
      required: false,
      default: null,
    },
    presetId: {
      type: String,
      required: false,
      default: '',
    },
    bulkItemIds: {
      type: Array,
      required: false,
      default: () => [],
    },
    detailsOnly: {
      type: Boolean,
      required: false,
      default: false,
    },
    profile: {
      type: Object,
      required: false,
      default: null,
    },
  },
  emits: ['close', 'applied'],
  data() {
    return {
      allProfiles: [],
      selectedId: '',
      hasLoadError: false,
      isConfirming: false,
      isApplying: false,
      isHidden: false,
    };
  },
  apollo: {
    allProfiles: {
      query: groupAvailableSecurityScanProfilesQuery,
      skip() {
        return !this.open || this.detailsOnly;
      },
      variables() {
        return { fullPath: this.groupFullPath, gitlabRecommended: true };
      },
      update(data) {
        return data?.group?.availableSecurityScanProfiles ?? [];
      },
      result({ data }) {
        if (!data) return;

        this.hasLoadError = false;
      },
      error(error) {
        this.hasLoadError = true;
        createAlert({
          message: s__('SecurityConfiguration|Failed to load triage and remediation profiles.'),
          containerSelector: `.${FLASH_CONTAINER_CLASS}`,
        });
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    presets() {
      if (this.detailsOnly) {
        return this.profile ? [this.profile] : [];
      }

      return getTriagePresets(this.allProfiles);
    },
    selectedPreset() {
      return (
        this.presets.find(({ id }) => id === this.selectedId) ??
        this.presets.find(({ id }) => id === this.presetId) ??
        this.presets.find(this.isRecommended) ??
        this.presets[0]
      );
    },
    isLoading() {
      return this.$apollo.queries.allProfiles.loading;
    },
    generalDetails() {
      return [
        { label: i18n.description, value: this.selectedPreset.description },
        { label: i18n.profileType, value: scanTypeName(this.selectedPreset.scanType) },
        { label: i18n.managedBy, value: managedByLabel(this.selectedPreset), isBadge: true },
      ];
    },
    isSelectedApplied() {
      return this.isApplied(this.selectedPreset);
    },
    isBulk() {
      return this.bulkItemIds.length > 0;
    },
    groupIds() {
      return this.bulkItemIds.filter((id) => id.includes('Group'));
    },
    projectIds() {
      return this.project
        ? [this.project.id]
        : this.bulkItemIds.filter((id) => id.includes('Project'));
    },
    selectionLabel() {
      return selectionLabel(this.projectIds.length, this.groupIds.length);
    },
    title() {
      if (this.detailsOnly) {
        return s__('SecurityConfiguration|Automated Triage and Remediation profile details');
      }

      if (!this.isBulk) {
        return s__('SecurityConfiguration|Select an Automated Triage and Remediation profile');
      }

      return n__(
        'SecurityConfiguration|Select an Automated Triage and Remediation profile for %d item',
        'SecurityConfiguration|Select an Automated Triage and Remediation profile for %d items',
        this.bulkItemIds.length,
      );
    },
    applyProfileTooltip() {
      return this.isSelectedApplied
        ? s__('SecurityConfiguration|This profile is already applied.')
        : '';
    },
  },
  watch: {
    open(isOpen) {
      if (isOpen) {
        this.selectedId = '';
        this.isHidden = false;
      }
    },
  },
  methods: {
    isSelected(preset) {
      return preset.id === this.selectedPreset?.id;
    },
    isRecommended(preset) {
      return preset.name === STANDARD_TRIAGE_PRESET_NAME;
    },
    isApplied(preset) {
      return Boolean(this.project) && preset.id === this.presetId;
    },
    handleDrawerClose() {
      if (this.isConfirming || this.isApplying) return;

      this.$emit('close');
    },
    confirmSwitch() {
      const appliedPreset = this.presets.find(({ id }) => id === this.presetId);
      if (!appliedPreset) return true;

      return confirmAction(
        sprintf(
          s__(
            'SecurityConfiguration|New vulnerabilities use %{newPreset}. Existing ones keep what %{oldPreset} already did.',
          ),
          { newPreset: this.selectedPreset.name, oldPreset: appliedPreset.name },
        ),
        {
          title: sprintf(s__('SecurityConfiguration|Switch to %{preset}?'), {
            preset: this.selectedPreset.name,
          }),
          primaryBtnText: s__('SecurityConfiguration|Switch profile'),
        },
      );
    },
    confirmBulkApply() {
      const preset = this.selectedPreset.name;

      return confirmAction(
        sprintf(s__('SecurityConfiguration|%{preset} uses GitLab Credits.'), { preset }),
        {
          title: sprintf(s__('SecurityConfiguration|Apply %{preset} to %{selection}?'), {
            preset,
            selection: this.selectionLabel,
          }),
          primaryBtnText: s__('SecurityConfiguration|Apply profile'),
        },
      );
    },
    // The drawer is hidden while the bulk confirmation and request run, so the alert
    // container exists only once it is shown again.
    async showAlert(message) {
      this.isHidden = false;
      await this.$nextTick();
      createAlert({ message, containerSelector: `.${FLASH_CONTAINER_CLASS}` });
    },
    async applyPreset() {
      if (this.isConfirming || this.isApplying) return;

      this.isConfirming = true;
      this.isHidden = this.isBulk;
      let confirmed;
      try {
        confirmed = await (this.isBulk ? this.confirmBulkApply() : this.confirmSwitch());
      } finally {
        this.isConfirming = false;
      }
      if (!confirmed) {
        if (this.isBulk) this.$emit('close');
        return;
      }

      this.isApplying = true;
      try {
        const { data } = await this.$apollo.mutate({
          mutation: attachMutation,
          variables: {
            input: {
              securityScanProfileId: this.selectedPreset.id,
              groupIds: this.groupIds,
              projectIds: this.projectIds,
            },
          },
        });

        const errors = data?.securityScanProfileAttach?.errors ?? [];
        if (errors.length) {
          await this.showAlert(errors.join(', '));
          return;
        }

        this.$toast.show(
          this.isBulk
            ? sprintf(s__('SecurityConfiguration|%{preset} applied to %{selection}.'), {
                preset: this.selectedPreset.name,
                selection: this.selectionLabel,
              })
            : SCAN_PROFILE_I18N.successApplying,
        );
        this.$emit('applied', this.selectedPreset);
        this.$emit('close');
      } catch (error) {
        await this.showAlert(SCAN_PROFILE_I18N.errorApplying);
        Sentry.captureException(error);
      } finally {
        this.isApplying = false;
      }
    },
  },
  EMPTY_STATE_SVG,
  FLASH_CONTAINER_CLASS,
  i18n,
};
</script>

<template>
  <profile-list-drawer
    :open="open && !isHidden"
    :title="title"
    :loading="isLoading"
    :error="hasLoadError"
    :narrow="detailsOnly"
    :show-list="!detailsOnly"
    :empty="!presets.length"
    data-testid="triage-profile-drawer"
    @close="handleDrawerClose"
  >
    <div :class="$options.FLASH_CONTAINER_CLASS" class="empty:gl-hidden"></div>

    <template #empty>
      <gl-empty-state
        :svg-path="$options.EMPTY_STATE_SVG"
        :title="s__('SecurityConfiguration|No profiles available')"
        :description="
          s__(
            'SecurityConfiguration|No Automated Triage and Remediation profiles are available for this group.',
          )
        "
        data-testid="triage-profile-empty"
      />
    </template>

    <template #list>
      <ul class="gl-m-0 gl-list-none gl-p-0" data-testid="triage-profile-list">
        <li v-for="preset in presets" :key="preset.id" class="gl-mr-5">
          <button
            type="button"
            class="gl-w-full gl-cursor-pointer gl-rounded-base gl-border-0 gl-bg-transparent gl-px-4 gl-py-3 gl-text-left"
            :class="{ '!gl-bg-feedback-info': isSelected(preset) }"
            :aria-current="isSelected(preset) ? 'true' : null"
            data-testid="triage-profile-list-item"
            @click="selectedId = preset.id"
          >
            <span class="gl-flex gl-flex-wrap gl-items-center gl-gap-2">
              <span class="gl-font-bold gl-text-default">{{ preset.name }}</span>
              <gl-badge v-if="isApplied(preset)" variant="success" data-testid="applied-badge">
                {{ __('Applied') }}
              </gl-badge>
              <gl-badge
                v-else-if="isRecommended(preset)"
                variant="info"
                data-testid="recommended-badge"
              >
                {{ __('Recommended') }}
              </gl-badge>
            </span>
            <span class="gl-mt-1 gl-line-clamp-2 gl-text-sm gl-text-subtle">
              {{ preset.description }}
            </span>
          </button>
        </li>
      </ul>
    </template>

    <template #detail>
      <div v-if="selectedPreset" data-testid="triage-profile-detail">
        <div class="gl-mb-5 gl-flex gl-items-start gl-justify-between gl-gap-3">
          <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-2">
            <h3 class="gl-heading-3 gl-mb-0">{{ selectedPreset.name }}</h3>
            <gl-badge
              v-if="isApplied(selectedPreset)"
              variant="success"
              data-testid="detail-applied-badge"
            >
              {{ __('Applied') }}
            </gl-badge>
            <gl-badge
              v-else-if="isRecommended(selectedPreset)"
              variant="info"
              data-testid="detail-recommended-badge"
            >
              {{ __('Recommended') }}
            </gl-badge>
          </div>
          <span
            v-if="(project || isBulk) && !detailsOnly"
            v-gl-tooltip
            :title="applyProfileTooltip"
            class="gl-inline-block gl-shrink-0"
            data-testid="apply-profile-button-wrapper"
          >
            <gl-button
              variant="confirm"
              :disabled="isSelectedApplied"
              :loading="isApplying"
              data-testid="apply-profile-button"
              @click="applyPreset"
            >
              {{ s__('SecurityConfiguration|Apply profile') }}
            </gl-button>
          </span>
        </div>
        <gl-tabs>
          <gl-tab :title="s__('SecurityConfiguration|Configuration')">
            <crud-component class="gl-mb-5" :title="$options.i18n.generalDetails">
              <dl class="gl-m-0 gl-flex gl-flex-col gl-gap-3">
                <div
                  v-for="{ label, value, isBadge } in generalDetails"
                  :key="label"
                  class="gl-flex gl-gap-3"
                >
                  <dt class="gl-w-1/3 gl-font-normal gl-text-subtle">{{ label }}</dt>
                  <dd class="gl-m-0 gl-flex-1">
                    <gl-badge v-if="isBadge">{{ value }}</gl-badge>
                    <template v-else>{{ value }}</template>
                  </dd>
                </div>
              </dl>
            </crud-component>
            <triage-preset-capabilities
              :triggers="selectedPreset.triggers"
              :trigger-settings="selectedPreset.triggerSettings"
            />
          </gl-tab>
        </gl-tabs>
      </div>
    </template>
  </profile-list-drawer>
</template>
