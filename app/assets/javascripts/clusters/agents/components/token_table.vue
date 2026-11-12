<script>
import { GlEmptyState, GlTable, GlTooltip, GlTruncate } from '@gitlab/ui';
import { s__ } from '~/locale';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import CreateTokenButton from './create_token_button.vue';
import CreateTokenModal from './create_token_modal.vue';
import RevokeTokenButton from './revoke_token_button.vue';

export default {
  name: 'TokenTable',
  components: {
    GlEmptyState,
    GlTable,
    GlTooltip,
    GlTruncate,
    TimeAgoTooltip,
    CreateTokenButton,
    CreateTokenModal,
    RevokeTokenButton,
  },
  props: {
    tokens: {
      required: true,
      type: Array,
    },
    clusterAgentId: {
      required: true,
      type: String,
    },
    cursor: {
      required: true,
      type: Object,
    },
  },
  computed: {
    fields() {
      const tdClass = '!gl-align-middle';
      return [
        {
          key: 'name',
          label: s__('ClusterAgents|Name'),
          tdAttr: { 'data-testid': 'agent-token-name' },
          tdClass,
        },
        {
          key: 'lastUsed',
          label: s__('ClusterAgents|Last contact'),
          tdAttr: { 'data-testid': 'agent-token-used' },
          tdClass,
        },
        {
          key: 'createdAt',
          label: s__('ClusterAgents|Date created'),
          tdAttr: { 'data-testid': 'agent-token-created-time' },
          tdClass,
        },
        {
          key: 'createdBy',
          label: s__('ClusterAgents|Created by'),
          tdAttr: { 'data-testid': 'agent-token-created-user' },
          tdClass,
        },
        {
          key: 'description',
          label: s__('ClusterAgents|Description'),
          tdAttr: { 'data-testid': 'agent-token-description' },
          tdClass,
        },
        {
          key: 'actions',
          label: '',
          tdAttr: { 'data-testid': 'agent-token-revoke' },
          tdClass,
        },
      ];
    },
  },
  methods: {
    createdByName(token) {
      return token?.createdByUser?.name || s__('ClusterAgents|Unknown user');
    },
  },
};
</script>

<template>
  <div>
    <div v-if="tokens.length">
      <create-token-button class="gl-my-5 gl-text-right" />

      <gl-table
        :items="tokens"
        :fields="fields"
        fixed
        stacked="md"
        head-variant="white"
        thead-class="gl-border-b-solid gl-border-b-2 gl-border-b-default"
      >
        <template #cell(lastUsed)="{ item }">
          <time-ago-tooltip v-if="item.lastUsedAt" :time="item.lastUsedAt" />
          <span v-else>{{ s__('ClusterAgents|Never') }}</span>
        </template>

        <template #cell(createdAt)="{ item }">
          <time-ago-tooltip :time="item.createdAt" />
        </template>

        <template #cell(createdBy)="{ item }">
          <span>{{ createdByName(item) }}</span>
        </template>

        <template #cell(description)="{ item }">
          <div v-if="item.description" :id="`tooltip-description-container-${item.id}`">
            <gl-truncate :id="`tooltip-description-${item.id}`" :text="item.description" />

            <gl-tooltip
              :container="`tooltip-description-container-${item.id}`"
              :target="`tooltip-description-${item.id}`"
              placement="top"
            >
              {{ item.description }}
            </gl-tooltip>
          </div>
        </template>

        <template #cell(actions)="{ item }">
          <revoke-token-button :token="item" :cluster-agent-id="clusterAgentId" :cursor="cursor" />
        </template>
      </gl-table>
    </div>

    <gl-empty-state v-else :title="s__('ClusterAgents|This agent has no tokens')">
      <template #actions>
        <create-token-button />
      </template>
    </gl-empty-state>

    <create-token-modal :cluster-agent-id="clusterAgentId" :cursor="cursor" />
  </div>
</template>
