<script>
import { GlButton, GlFormGroup, GlFormInput, GlModal, GlSprintf } from '@gitlab/ui';
import csrf from '~/lib/utils/csrf';
import { __, s__ } from '~/locale';
import eventHub from '../event_hub';

export default {
  name: 'DeleteBranchModal',
  csrf,
  components: {
    GlModal,
    GlButton,
    GlFormGroup,
    GlFormInput,
    GlSprintf,
  },
  data() {
    return {
      isProtectedBranch: false,
      branchName: '',
      defaultBranchName: '',
      deletePath: '',
      merged: false,
      enteredBranchName: '',
      modalId: 'delete-branch-modal',
    };
  },
  computed: {
    title() {
      return this.isProtectedBranch
        ? this.$options.i18n.modalTitleProtectedBranch
        : this.$options.i18n.modalTitle;
    },
    modalMessage() {
      return this.isProtectedBranch
        ? this.$options.i18n.modalMessageProtectedBranch
        : this.$options.i18n.modalMessage;
    },
    buttonText() {
      return this.isProtectedBranch
        ? this.$options.i18n.deleteButtonTextProtectedBranch
        : this.$options.i18n.deleteButtonText;
    },
    branchNameConfirmed() {
      return this.enteredBranchName === this.branchName;
    },
    deleteButtonDisabled() {
      return this.isProtectedBranch && !this.branchNameConfirmed;
    },
  },
  mounted() {
    eventHub.$on('open-modal', this.openModal);
  },
  destroyed() {
    eventHub.$off('open-modal', this.openModal);
  },
  methods: {
    openModal({ isProtectedBranch, branchName, defaultBranchName, deletePath, merged }) {
      this.isProtectedBranch = isProtectedBranch;
      this.branchName = branchName;
      this.defaultBranchName = defaultBranchName;
      this.deletePath = deletePath;
      this.merged = merged;
      this.enteredBranchName = '';

      this.$refs.modal.show();
    },
    submitForm() {
      if (!this.deleteButtonDisabled) {
        this.$refs.form.submit();
      }
    },
    closeModal() {
      this.$refs.modal.hide();
    },
  },
  i18n: {
    modalTitle: s__('Branches|Delete branch?'),
    modalTitleProtectedBranch: s__('Branches|Delete protected branch?'),
    modalMessage: s__(
      "Branches|You're about to permanently delete the branch %{branchName}. This cannot be undone.",
    ),
    modalMessageProtectedBranch: s__(
      "Branches|You're about to permanently delete the protected branch %{branchName}. This cannot be undone.",
    ),
    unmergedWarning: s__(
      "Branches|This branch hasn't been merged into %{defaultBranchName}. To avoid data loss, consider merging this branch before deleting it.",
    ),
    cancelButtonText: __('Cancel'),
    confirmationTextProtectedBranch: __('Enter the following to confirm: %{phrase}'),
    deleteButtonText: s__('Branches|Delete branch'),
    deleteButtonTextProtectedBranch: s__('Branches|Delete protected branch'),
  },
};
</script>

<template>
  <gl-modal ref="modal" size="sm" :modal-id="modalId" :title="title">
    <div data-testid="modal-message">
      <p>
        <gl-sprintf :message="modalMessage">
          <template #branchName>
            <strong>
              <code class="gl-whitespace-pre-wrap">{{ branchName }}</code>
            </strong>
          </template>
        </gl-sprintf>
      </p>
      <p v-if="!merged" class="gl-text-danger">
        <gl-sprintf :message="$options.i18n.unmergedWarning">
          <template #defaultBranchName>
            <code class="gl-whitespace-pre-wrap">{{ defaultBranchName }}</code>
          </template>
        </gl-sprintf>
      </p>
    </div>

    <form ref="form" :action="deletePath" method="post" @submit.prevent="submitForm">
      <gl-form-group v-if="isProtectedBranch" label-for="delete-branch-input">
        <template #label>
          <gl-sprintf :message="$options.i18n.confirmationTextProtectedBranch">
            <template #phrase>
              <code class="gl-whitespace-pre-wrap">{{ branchName }}</code>
            </template>
          </gl-sprintf>
        </template>
        <gl-form-input
          id="delete-branch-input"
          v-model="enteredBranchName"
          name="delete_branch_input"
          type="text"
          autocomplete="off"
        />
      </gl-form-group>

      <input ref="method" type="hidden" name="_method" value="delete" />
      <input :value="$options.csrf.token" type="hidden" name="authenticity_token" />
    </form>

    <template #modal-footer>
      <div class="gl-m-0 gl-flex gl-flex-row gl-flex-wrap gl-justify-end">
        <gl-button data-testid="delete-branch-cancel-button" @click="closeModal">
          {{ $options.i18n.cancelButtonText }}
        </gl-button>
        <div class="gl-mr-3"></div>
        <gl-button
          ref="deleteBranchButton"
          :disabled="deleteButtonDisabled"
          variant="danger"
          data-testid="delete-branch-confirmation-button"
          @click="submitForm"
          >{{ buttonText }}</gl-button
        >
      </div>
    </template>
  </gl-modal>
</template>
