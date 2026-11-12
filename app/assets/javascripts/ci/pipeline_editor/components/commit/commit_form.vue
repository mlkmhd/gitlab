<script>
import {
  GlButton,
  GlForm,
  GlFormCheckbox,
  GlFormInput,
  GlFormGroup,
  GlFormTextarea,
  GlSprintf,
} from '@gitlab/ui';

export default {
  name: 'CommitForm',
  components: {
    GlButton,
    GlForm,
    GlFormCheckbox,
    GlFormInput,
    GlFormGroup,
    GlFormTextarea,
    GlSprintf,
  },
  props: {
    currentBranch: {
      type: String,
      required: false,
      default: '',
    },
    defaultMessage: {
      type: String,
      required: false,
      default: '',
    },
    hasUnsavedChanges: {
      type: Boolean,
      required: true,
    },
    isNewCiConfigFile: {
      type: Boolean,
      required: true,
    },
    isSaving: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['submit', 'reset-content'],
  expose: ['resetCommitMessage'],
  data() {
    return {
      message: this.defaultMessage,
      openMergeRequest: false,
      sourceBranch: this.currentBranch,
    };
  },
  computed: {
    isCommitFormFilledOut() {
      return this.message && this.sourceBranch;
    },
    isCurrentBranchSourceBranch() {
      return this.sourceBranch === this.currentBranch;
    },
    isSubmitDisabled() {
      return !this.isCommitFormFilledOut || (!this.hasUnsavedChanges && !this.isNewCiConfigFile);
    },
  },
  methods: {
    onSubmit() {
      this.$emit('submit', {
        message: this.message,
        sourceBranch: this.sourceBranch,
        openMergeRequest: this.openMergeRequest,
      });
    },
    onReset() {
      this.$emit('reset-content');
    },
    resetCommitMessage() {
      this.message = this.defaultMessage;
    },
  },
};
</script>

<template>
  <div>
    <gl-form @submit.prevent="onSubmit" @reset.prevent="onReset">
      <gl-form-group id="commit-group" :label="__('Commit message')" label-for="commit-message">
        <gl-form-textarea
          id="commit-message"
          v-model="message"
          class="!gl-font-monospace"
          required
          no-resize
          :placeholder="defaultMessage"
        />
      </gl-form-group>
      <gl-form-group id="source-branch-group" :label="__('Branch')" label-for="source-branch-field">
        <gl-form-input
          id="source-branch-field"
          v-model="sourceBranch"
          class="!gl-font-monospace"
          required
          data-testid="source-branch-field"
        />
        <gl-form-checkbox
          v-if="!isCurrentBranchSourceBranch"
          v-model="openMergeRequest"
          data-testid="new-mr-checkbox"
          class="gl-mt-3"
        >
          <gl-sprintf :message="__('Start a %{new_merge_request} with these changes')">
            <template #new_merge_request>
              <strong>{{ __('new merge request') }}</strong>
            </template>
          </gl-sprintf>
        </gl-form-checkbox>
      </gl-form-group>
      <div class="gl-flex gl-py-5">
        <gl-button
          type="submit"
          class="js-no-auto-disable gl-mr-3"
          category="primary"
          variant="confirm"
          data-testid="commit-changes-button"
          :disabled="isSubmitDisabled"
          :loading="isSaving"
        >
          {{ __('Commit changes') }}
        </gl-button>
        <gl-button type="reset" category="secondary" class="gl-mr-3">
          {{ __('Reset') }}
        </gl-button>
      </div>
    </gl-form>
  </div>
</template>
