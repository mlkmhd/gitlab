<script>
import { GlLink, GlSprintf } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';

export default {
  name: 'NewCluster',
  clusterConnectHelpPath: helpPagePath('user/project/clusters/add_existing_cluster'),
  components: {
    GlLink,
    GlSprintf,
  },
};
</script>

<template>
  <div class="gl-pt-4">
    <h4>{{ s__('ClusterIntegration|Enter your Kubernetes cluster certificate details') }}</h4>
    <p data-testid="description">
      <gl-sprintf
        :message="
          s__(
            'ClusterIntegration|Enter details about your cluster. %{linkStart}How do I use a certificate to connect to my cluster?%{linkEnd}',
          )
        "
      >
        <template #link="{ content }">
          <gl-link :href="$options.clusterConnectHelpPath">{{ content }}</gl-link>
        </template>
      </gl-sprintf>
    </p>
  </div>
</template>
