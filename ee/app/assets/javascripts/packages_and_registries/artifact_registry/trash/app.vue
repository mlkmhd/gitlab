<script>
import PageHeading from '~/vue_shared/components/page_heading.vue';

export default {
  name: 'ArtifactRegistryTrashApp',
  components: {
    PageHeading,
  },
};
</script>

<template>
  <page-heading :heading="s__('ArtifactRegistry|Trash')" />
</template>
