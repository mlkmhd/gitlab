<script>
import { GlEmptyState } from '@gitlab/ui';
import { s__ } from '~/locale';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import { SOFTWARE_FACTORY_TITLE } from './constants';

export default {
  name: 'SoftwareFactoryPage',
  components: {
    GlEmptyState,
    PageHeading,
  },
  SOFTWARE_FACTORY_TITLE,
  emptyState: {
    title: s__('DapSoftwareFactory|No stages configured'),
    description: s__('DapSoftwareFactory|Stages for this project will appear here.'),
  },
};
</script>

<template>
  <div>
    <page-heading :heading="$options.SOFTWARE_FACTORY_TITLE" />
    <gl-empty-state
      :title="$options.emptyState.title"
      :description="$options.emptyState.description"
    />
  </div>
</template>
