<script>
import { GlEmptyState, GlButton, GlModalDirective } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import InitCommandModal from './init_command_modal.vue';

export default {
  name: 'EmptyState',
  COMMAND_MODAL_ID: 'init-command-modal',
  docsUrl: helpPagePath('user/infrastructure/iac/terraform_state'),
  components: {
    GlEmptyState,
    GlButton,
    InitCommandModal,
  },

  directives: {
    GlModalDirective,
  },

  props: {
    image: {
      type: String,
      required: true,
    },
  },
};
</script>

<template>
  <gl-empty-state
    :svg-path="image"
    :svg-height="null"
    :title="s__('Terraform|Your project doesn\'t have any Terraform state files')"
  >
    <template #actions>
      <gl-button variant="confirm" :href="$options.docsUrl" class="gl-mx-2 gl-mb-3">
        {{ s__('Terraform|Explore documentation') }}</gl-button
      >
      <gl-button
        v-gl-modal-directive="$options.COMMAND_MODAL_ID"
        class="gl-mx-2 gl-mb-3"
        data-testid="terraform-state-copy-init-command"
        icon="copy-to-clipboard"
        >{{ s__('Terraform|Copy Terraform init command') }}</gl-button
      >

      <init-command-modal :modal-id="$options.COMMAND_MODAL_ID" />
    </template>
  </gl-empty-state>
</template>
