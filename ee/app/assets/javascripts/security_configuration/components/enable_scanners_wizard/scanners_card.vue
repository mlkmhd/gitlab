<script>
import { GlCard, GlIcon, GlButton, GlTableLite, GlTooltipDirective } from '@gitlab/ui';
import { __ } from '~/locale';
import ScanProfileDetailsModal from 'ee/security_configuration/components/scan_profiles/scan_profile_details_modal.vue';
import ScanTypeCell from '~/security_configuration/components/scan_profiles/scan_type_cell.vue';

export default {
  name: 'EnableScannersCard',
  components: {
    GlCard,
    GlIcon,
    GlButton,
    GlTableLite,
    ScanProfileDetailsModal,
    ScanTypeCell,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  inject: ['wizard'],
  props: {
    editable: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  data() {
    return {
      previewProfile: null,
    };
  },
  methods: {
    openPreview(profile) {
      this.previewProfile = profile;
    },
    closePreview() {
      this.previewProfile = null;
    },
  },
  scannerFields: [
    { key: 'scanType', label: __('Scanner'), thClass: 'gl-w-1/2', tdClass: '!gl-align-middle' },
    { key: 'name', label: __('Profile'), thClass: 'gl-w-1/2', tdClass: '!gl-align-middle' },
  ],
};
</script>
<template>
  <gl-card class="gl-my-5">
    <template #header>
      <div class="gl-flex gl-items-center gl-justify-between">
        <span class="gl-flex gl-items-center gl-gap-2">
          <gl-icon name="shield" />
          <strong>{{ __('Scanners') }}</strong>
        </span>
        <gl-button
          v-if="editable"
          v-gl-tooltip
          :aria-label="s__('SecurityConfiguration|Edit scanners')"
          :title="s__('SecurityConfiguration|Edit scanners')"
          icon="pencil"
          category="tertiary"
          size="small"
          data-testid="edit-scanners-button"
          :to="{ name: wizard.routes.profiles }"
        />
      </div>
    </template>
    <gl-table-lite
      :fields="$options.scannerFields"
      :items="wizard.selectedProfiles"
      table-class="!gl-bg-transparent"
      data-testid="scanners-table"
      borderless
    >
      <template #cell(scanType)="{ item }">
        <scan-type-cell :scan-type="item.scanType" solid />
      </template>
      <template #cell(name)="{ item }">
        <gl-button variant="link" data-testid="preview-profile-link" @click="openPreview(item)">
          {{ item.name }}
        </gl-button>
      </template>
    </gl-table-lite>

    <scan-profile-details-modal
      :profile-id="previewProfile?.id ?? ''"
      :scan-type="previewProfile?.scanType ?? ''"
      :visible="Boolean(previewProfile)"
      :with-apply-action="false"
      @close="closePreview"
    />
  </gl-card>
</template>
