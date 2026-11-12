<script>
import AgentArtifactsFilteredSearch from 'ee/agent_artifacts/components/agent_artifacts_filtered_search.vue';
import AgentArtifactsTable from 'ee/agent_artifacts/components/agent_artifacts_table.vue';

export default {
  name: 'AuditEventsPanelView',
  components: {
    AgentArtifactsFilteredSearch,
    AgentArtifactsTable,
  },
  props: {
    filters: {
      type: Object,
      required: true,
    },
  },
  emits: ['open-session'],
  data() {
    return {
      filter: {},
    };
  },
};
</script>

<template>
  <div>
    <agent-artifacts-filtered-search :initial-filters="filters" @filter="filter = $event" />

    <agent-artifacts-table
      class="gl-mt-5"
      :filter="filter"
      @row-click="$emit('open-session', $event)"
    />
  </div>
</template>
