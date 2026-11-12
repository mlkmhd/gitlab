<script>
import { GlDisclosureDropdown, GlDisclosureDropdownItem } from '@gitlab/ui';
import { s__ } from '~/locale';
import glFeatureFlagMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import {
  ACTION_TYPE_BULK_EDIT_ATTRIBUTES,
  ACTION_TYPE_BULK_EDIT_SCANNERS,
  ACTION_TYPE_BULK_EDIT_TRIAGE,
  ACTION_TYPE_BULK_TURN_OFF_TRIAGE,
} from '../constants';

export default {
  name: 'BulkEditActionsDropdown',
  components: {
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
  },
  mixins: [glFeatureFlagMixin()],
  inject: ['canManageAttributes', 'canApplyProfiles', 'canReadScanProfiles'],
  emits: ['bulk-edit'],
  computed: {
    availableActions() {
      const actions = [];

      if (this.canApplyProfiles) {
        actions.push({
          text: s__('SecurityInventory|Manage security scanners'),
          type: ACTION_TYPE_BULK_EDIT_SCANNERS,
        });
      }
      if (this.canManageAttributes) {
        actions.push({
          text: s__('SecurityAttributes|Manage security attributes'),
          type: ACTION_TYPE_BULK_EDIT_ATTRIBUTES,
        });
      }
      if (
        this.canApplyProfiles &&
        this.canReadScanProfiles &&
        this.glFeatures.triageAndRemediationProfilesUi
      ) {
        actions.push({
          text: s__('SecurityInventory|Apply Automated Triage and Remediation profile'),
          type: ACTION_TYPE_BULK_EDIT_TRIAGE,
        });
        actions.push({
          text: s__('SecurityInventory|Turn off Automated Triage and Remediation'),
          type: ACTION_TYPE_BULK_TURN_OFF_TRIAGE,
        });
      }

      return actions;
    },
  },
};
</script>

<template>
  <gl-disclosure-dropdown
    :toggle-text="s__('SecurityInventory|Select bulk action')"
    :items="availableActions"
    :disabled="availableActions.length === 0"
  >
    <gl-disclosure-dropdown-item
      v-for="action in availableActions"
      :key="action.type"
      :item="action"
      @action="$emit('bulk-edit', action.type)"
    />
  </gl-disclosure-dropdown>
</template>
