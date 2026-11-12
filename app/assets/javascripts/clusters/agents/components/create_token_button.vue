<script>
import { GlButton, GlModalDirective, GlTooltip } from '@gitlab/ui';
import { CREATE_TOKEN_MODAL } from '../constants';

export default {
  name: 'CreateTokenButton',
  components: {
    GlButton,
    GlTooltip,
  },
  directives: {
    GlModalDirective,
  },
  inject: ['canAdminCluster'],
  modalId: CREATE_TOKEN_MODAL,
};
</script>

<template>
  <div>
    <div ref="addToken" class="gl-inline-block">
      <gl-button
        v-gl-modal-directive="$options.modalId"
        :disabled="!canAdminCluster"
        category="primary"
        variant="confirm"
        >{{ s__('ClusterAgents|Create token') }}
      </gl-button>

      <gl-tooltip
        v-if="!canAdminCluster"
        :target="() => $refs.addToken"
        :title="s__('ClusterAgents|Requires a Maintainer or greater role to perform these actions')"
      />
    </div>
  </div>
</template>
