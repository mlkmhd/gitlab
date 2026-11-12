<script>
import { GlEmptyState } from '@gitlab/ui';

export default {
  name: 'ReleasesEmptyState',
  components: {
    GlEmptyState,
  },
  inject: {
    documentationPath: { default: null },
    illustrationPath: { default: null },
    newReleasePath: { default: null },
  },
};
</script>
<template>
  <gl-empty-state
    class="gl-mx-auto gl-max-w-limited"
    :title="s__('Release|Getting started with releases')"
    :description="
      s__(
        'Release|Releases are based on Git tags and mark specific points in a project\'s development history. They can contain information about the type of changes and can also deliver binaries, like compiled versions of your software.',
      )
    "
    :svg-path="illustrationPath"
    :primary-button-link="newReleasePath"
    :primary-button-text="s__('Release|Create a new release')"
    :secondary-button-link="documentationPath"
    :secondary-button-text="s__('Release|Learn more about releases')"
  />
</template>
