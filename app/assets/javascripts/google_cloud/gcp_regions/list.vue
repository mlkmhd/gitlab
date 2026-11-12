<script>
import { GlButton, GlEmptyState, GlTable } from '@gitlab/ui';
import { __ } from '~/locale';

export default {
  name: 'GcpRegionsList',
  components: { GlButton, GlEmptyState, GlTable },
  props: {
    list: {
      type: Array,
      required: true,
    },
    createUrl: {
      type: String,
      required: true,
    },
  },
  tableFields: [
    { key: 'environment', label: __('Environment'), sortable: true, isRowHeader: true },
    { key: 'gcp_region', label: __('Region'), sortable: true },
  ],
  i18n: {
    description: __('Configure your environments to be deployed to specific geographical regions'),
    configureRegions: __('Configure regions'),
  },
};
</script>

<template>
  <div>
    <gl-empty-state
      v-if="list.length === 0"
      :title="__('No regions configured')"
      :description="$options.i18n.description"
      :primary-button-link="createUrl"
      :primary-button-text="$options.i18n.configureRegions"
    />

    <div v-else>
      <h2 class="gl-text-size-h2">{{ __('Regions') }}</h2>
      <p>{{ $options.i18n.description }}</p>

      <gl-table :items="list" :fields="$options.tableFields" />

      <gl-button :href="createUrl" category="primary" variant="confirm">
        {{ $options.i18n.configureRegions }}
      </gl-button>
    </div>
  </div>
</template>
