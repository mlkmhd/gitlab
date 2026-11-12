<script>
import emptyEnvironmentsSvgPath from '@gitlab/svgs/dist/illustrations/empty-state/empty-environment-md.svg';
import { GlButton, GlEmptyState, GlLink, GlSprintf } from '@gitlab/ui';
import EmptyResult from '~/vue_shared/components/empty_result.vue';

export default {
  name: 'EnvironmentsEmptyState',
  components: {
    GlButton,
    GlEmptyState,
    GlLink,
    GlSprintf,
    EmptyResult,
  },
  inject: ['newEnvironmentPath'],
  props: {
    helpPath: {
      type: String,
      required: true,
    },
    hasTerm: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['enable-review'],
  emptyEnvironmentsSvgPath,
};
</script>
<template>
  <empty-result v-if="hasTerm" type="search" />
  <gl-empty-state
    v-else
    class="gl-mx-auto gl-max-w-limited"
    :title="s__('Environments|Get started with environments')"
    :svg-path="$options.emptyEnvironmentsSvgPath"
  >
    <template #description>
      <gl-sprintf
        :message="
          s__(
            'Environments|Environments are places where code gets deployed, such as staging or production. You can create an environment in the UI or in your .gitlab-ci.yml file. You can also enable review apps, which assist with providing an environment to showcase product changes. %{linkStart}Learn more%{linkEnd} about environments.',
          )
        "
      >
        <template #link="{ content: contentToDisplay }">
          <gl-link :href="helpPath">{{ contentToDisplay }}</gl-link>
        </template>
      </gl-sprintf>
    </template>
    <template v-if="!hasTerm" #actions>
      <gl-button
        class="gl-mx-2 gl-mb-3"
        :href="newEnvironmentPath"
        variant="confirm"
        data-testid="new-environment-button"
      >
        {{ s__('Environments|Create an environment') }}
      </gl-button>
      <gl-button
        class="gl-mx-2 gl-mb-3"
        data-testid="enable-review-button"
        @click="$emit('enable-review')"
      >
        {{ s__('Environments|Enable review apps') }}
      </gl-button>
    </template>
  </gl-empty-state>
</template>
