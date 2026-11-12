<script>
import { GlModal } from '@gitlab/ui';
import { __ } from '~/locale';

export default {
  name: 'DeleteSubscriptionConfirmationModal',
  modal: {
    id: 'delete-subscription-modal',
    actionPrimary: {
      text: __('OK'),
      attributes: {
        variant: 'danger',
      },
    },
    actionCancel: {
      text: __('Cancel'),
      attributes: {
        variant: 'default',
      },
    },
  },
  components: {
    GlModal,
  },
  props: {
    isModalVisible: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['delete-confirmed', 'hide'],
};
</script>

<template>
  <gl-modal
    :modal-id="$options.modal.id"
    :title="s__('PipelineSubscriptions|Delete subscription')"
    :action-primary="$options.modal.actionPrimary"
    :action-cancel="$options.modal.actionCancel"
    :visible="isModalVisible"
    size="sm"
    @primary="$emit('delete-confirmed')"
    @hidden="$emit('hide')"
  >
    <p>
      {{
        s__(
          'PipelineSubscriptions|Subscription for this project will be removed. Do you want to continue?',
        )
      }}
    </p>
  </gl-modal>
</template>
