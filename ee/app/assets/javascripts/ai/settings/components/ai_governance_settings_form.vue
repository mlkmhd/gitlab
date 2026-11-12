<script>
import { GlFormCheckbox, GlToggle } from '@gitlab/ui';
import axios from '~/lib/utils/axios_utils';
import { createAlert, VARIANT_SUCCESS } from '~/alert';
import { s__ } from '~/locale';
import CascadingLockIcon from '~/namespaces/cascading_settings/components/cascading_lock_icon.vue';
import DuoAuditEventStorageForm from './duo_audit_event_storage_form.vue';

export default {
  name: 'AiGovernanceSettingsForm',
  components: {
    GlFormCheckbox,
    GlToggle,
    CascadingLockIcon,
    DuoAuditEventStorageForm,
  },
  inject: ['aiAuditEventsStorageEnabled', 'aiAuditEventsStorageCascadingSettings'],
  props: {
    initialAiGovernanceEnabled: {
      type: Boolean,
      required: true,
    },
    initialLockAiGovernanceEnabled: {
      type: Boolean,
      required: true,
    },
    initialLockAiAuditEventsStorageEnabled: {
      type: Boolean,
      required: true,
    },
    cascadingSettings: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    updatePath: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      aiGovernanceEnabled: this.initialAiGovernanceEnabled,
      lockAiGovernanceEnabled: this.initialLockAiGovernanceEnabled,
      auditEventsStorageEnabled: this.aiAuditEventsStorageEnabled,
      lockAiAuditEventsStorageEnabled: this.initialLockAiAuditEventsStorageEnabled,
      isSaving: false,
    };
  },
  computed: {
    isStorageLocked() {
      return Boolean(
        this.aiAuditEventsStorageCascadingSettings?.lockedByAncestor ||
        this.aiAuditEventsStorageCascadingSettings?.lockedByApplicationSetting,
      );
    },
    isLocked() {
      return Boolean(
        this.cascadingSettings.lockedByAncestor ||
        this.cascadingSettings.lockedByApplicationSetting,
      );
    },
  },
  methods: {
    async onToggleChange(value) {
      this.aiGovernanceEnabled = value;

      const saved = await this.save({ ai_governance_enabled: value });

      if (!saved) this.aiGovernanceEnabled = !value;
    },
    async onLockChange(value) {
      this.lockAiGovernanceEnabled = value;

      // The backend rejects locking an inherited (nil) value, so send the current value with the lock.
      const saved = await this.save({
        ai_governance_enabled: this.aiGovernanceEnabled,
        lock_ai_governance_enabled: value,
      });

      if (!saved) this.lockAiGovernanceEnabled = !value;
    },
    async onAuditEventsStorageChange(value) {
      this.auditEventsStorageEnabled = value;

      const saved = await this.save({ ai_audit_events_storage_enabled: value });

      if (!saved) this.auditEventsStorageEnabled = !value;
    },
    async onAuditEventsStorageLockChange(value) {
      this.lockAiAuditEventsStorageEnabled = value;

      // The backend rejects locking an inherited (nil) value, so send the current value with the lock.
      const saved = await this.save({
        ai_audit_events_storage_enabled: this.auditEventsStorageEnabled,
        lock_ai_audit_events_storage_enabled: value,
      });

      if (!saved) this.lockAiAuditEventsStorageEnabled = !value;
    },
    async save(group) {
      this.isSaving = true;

      try {
        await axios.patch(this.updatePath, { group });

        createAlert({
          message: s__('AiGovernance|AI Governance settings were successfully updated.'),
          variant: VARIANT_SUCCESS,
        });

        return true;
      } catch (error) {
        createAlert({
          message:
            error.response?.data?.message ||
            s__('AiGovernance|Failed to update the AI Governance settings.'),
          captureError: true,
          error,
        });

        return false;
      } finally {
        this.isSaving = false;
      }
    },
  },
};
</script>
<template>
  <div>
    <gl-toggle
      :value="aiGovernanceEnabled"
      :disabled="isLocked || isSaving"
      :is-loading="isSaving"
      data-testid="ai-governance-toggle"
      @change="onToggleChange"
    >
      <template #label>
        <span class="gl-inline-flex gl-items-center gl-gap-2">
          {{ s__('AiGovernance|Enable AI Governance') }}
          <cascading-lock-icon
            v-if="isLocked"
            data-testid="ai-governance-cascading-lock-icon"
            :is-locked-by-group-ancestor="Boolean(cascadingSettings.lockedByAncestor)"
            :is-locked-by-application-settings="
              Boolean(cascadingSettings.lockedByApplicationSetting)
            "
            :ancestor-namespace="cascadingSettings.ancestorNamespace"
          />
        </span>
      </template>
    </gl-toggle>

    <gl-form-checkbox
      v-if="!isLocked"
      :checked="lockAiGovernanceEnabled"
      :disabled="isSaving"
      class="gl-mt-5"
      data-testid="enforce-for-all-subgroups-checkbox"
      @change="onLockChange"
    >
      {{ s__('CascadingSettings|Enforce for all subgroups') }}
      <template #help>
        {{ s__('CascadingSettings|Subgroups cannot change this setting.') }}
      </template>
    </gl-form-checkbox>

    <duo-audit-event-storage-form
      class="gl-mt-5"
      :checked="auditEventsStorageEnabled"
      :disabled-checkbox="!aiGovernanceEnabled || isSaving"
      :disabled-tooltip="
        isSaving ? '' : s__('AiGovernance|Turn on AI Governance to change this setting.')
      "
      @change="onAuditEventsStorageChange"
    />

    <gl-form-checkbox
      v-if="!isStorageLocked"
      :checked="lockAiAuditEventsStorageEnabled"
      :disabled="!aiGovernanceEnabled || isSaving"
      data-testid="enforce-storage-for-all-subgroups-checkbox"
      @change="onAuditEventsStorageLockChange"
    >
      {{ s__('CascadingSettings|Enforce for all subgroups') }}
      <template #help>
        {{ s__('CascadingSettings|Subgroups cannot change this setting.') }}
      </template>
    </gl-form-checkbox>
  </div>
</template>
