<script>
import { GlModal } from '@gitlab/ui';
import { __, s__, sprintf } from '~/locale';

export default {
  name: 'OrganizationAccessLeaveModal',
  components: { GlModal },
  props: {
    resource: {
      type: Object,
      required: true,
    },
    member: {
      type: Object,
      required: false,
      default: null,
    },
  },
  emits: ['close', 'leave'],
  computed: {
    title() {
      return sprintf(s__('Members|Leave "%{source}"'), { source: this.resource.label });
    },
    body() {
      return sprintf(s__('Members|Are you sure you want to leave "%{source}"?'), {
        source: this.resource.label,
      });
    },
  },
  methods: {
    onPrimary() {
      this.$emit('leave', { member: this.member });
    },
  },
  modalId: 'organization-access-leave-modal',
  actionPrimary: { text: __('Leave'), attributes: { variant: 'danger' } },
  actionCancel: { text: __('Cancel') },
};
</script>

<template>
  <gl-modal
    :modal-id="$options.modalId"
    :visible="Boolean(member)"
    :title="title"
    :action-primary="$options.actionPrimary"
    :action-cancel="$options.actionCancel"
    @primary="onPrimary"
    @hidden="$emit('close')"
  >
    <p class="gl-mb-0">{{ body }}</p>
  </gl-modal>
</template>
