<script>
import { GlAlert, GlFormGroup, GlFormInput, GlFormTextarea, GlModal } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { __, n__, s__, sprintf } from '~/locale';

const COMMIT_MESSAGE = s__('DapSoftwareFactory|Update DAP Software Factory configuration');

const newBranchName = () => `dap-factory-config-${Date.now()}`;

export default {
  name: 'CommitModal',
  components: {
    GlAlert,
    GlFormGroup,
    GlFormInput,
    GlFormTextarea,
    GlModal,
  },
  props: {
    visible: {
      type: Boolean,
      required: true,
    },
    openMergeRequest: {
      type: Boolean,
      required: false,
      default: false,
    },
    defaultBranch: {
      type: String,
      required: true,
    },
    errorCount: {
      type: Number,
      required: false,
      default: 0,
    },
  },
  emits: ['submit', 'hide'],
  data() {
    return {
      message: COMMIT_MESSAGE,
      branch: newBranchName(),
      modalId: uniqueId('dap-factory-commit-modal-'),
      messageId: uniqueId('dap-factory-commit-message-'),
      branchId: uniqueId('dap-factory-commit-branch-'),
    };
  },
  computed: {
    title() {
      return this.openMergeRequest
        ? s__('DapSoftwareFactory|Open a merge request')
        : sprintf(s__('DapSoftwareFactory|Commit to %{branch}'), { branch: this.defaultBranch });
    },
    branchDescription() {
      return sprintf(s__('DapSoftwareFactory|A new branch is created from %{branch}.'), {
        branch: this.defaultBranch,
      });
    },
    canSubmit() {
      return (
        Boolean(this.message.trim()) && (!this.openMergeRequest || Boolean(this.branch.trim()))
      );
    },
    actionPrimary() {
      return {
        text: this.openMergeRequest
          ? s__('DapSoftwareFactory|Commit and open merge request')
          : s__('DapSoftwareFactory|Commit changes'),
        attributes: { variant: 'confirm', disabled: !this.canSubmit },
      };
    },
    actionCancel() {
      return { text: __('Cancel') };
    },
    errorWarning() {
      return sprintf(
        n__(
          'DapSoftwareFactory|The configuration has %{count} error. Sync does not apply it until the error is fixed.',
          'DapSoftwareFactory|The configuration has %{count} errors. Sync does not apply it until the errors are fixed.',
          this.errorCount,
        ),
        { count: this.errorCount },
      );
    },
  },
  methods: {
    reset() {
      this.message = COMMIT_MESSAGE;
      this.branch = newBranchName();
    },
    onPrimary() {
      if (!this.canSubmit) return;

      this.$emit('submit', {
        message: this.message.trim(),
        branch: this.openMergeRequest ? this.branch.trim() : '',
      });
    },
  },
};
</script>

<template>
  <gl-modal
    :visible="visible"
    :modal-id="modalId"
    :title="title"
    :action-primary="actionPrimary"
    :action-cancel="actionCancel"
    data-testid="commit-modal"
    @show="reset"
    @primary="onPrimary"
    @hide="$emit('hide')"
  >
    <gl-alert
      v-if="errorCount"
      variant="warning"
      :dismissible="false"
      class="gl-mb-5"
      data-testid="commit-modal-errors"
    >
      {{ errorWarning }}
    </gl-alert>
    <gl-form-group :label="s__('DapSoftwareFactory|Commit message')" :label-for="messageId">
      <gl-form-textarea
        :id="messageId"
        v-model="message"
        no-resize
        data-testid="commit-message-input"
      />
    </gl-form-group>
    <gl-form-group
      v-if="openMergeRequest"
      :label="s__('DapSoftwareFactory|Branch name')"
      :label-for="branchId"
      :description="branchDescription"
      class="gl-mb-0"
    >
      <gl-form-input :id="branchId" v-model="branch" data-testid="commit-branch-input" />
    </gl-form-group>
  </gl-modal>
</template>
