<script>
import { mapActions } from 'pinia';
import { s__ } from '~/locale';
import { useStatusChecks } from '../store';
import SharedModal from './shared_modal.vue';

export default {
  name: 'ModalUpdate',
  components: {
    SharedModal,
  },
  props: {
    statusCheck: {
      type: Object,
      required: true,
    },
  },
  methods: {
    ...mapActions(useStatusChecks, ['putStatusCheck']),
    // eslint-disable-next-line vue/no-unused-properties -- show() is part of the component's public API.
    show() {
      this.$refs.modal.show();
    },
  },
  modalId: 'status-checks-update-modal',
  i18n: {
    title: s__('StatusCheck|Update status check'),
  },
};
</script>

<template>
  <shared-modal
    ref="modal"
    :modal-id="$options.modalId"
    :title="$options.i18n.title"
    :status-check="statusCheck"
    :action="putStatusCheck"
  />
</template>
