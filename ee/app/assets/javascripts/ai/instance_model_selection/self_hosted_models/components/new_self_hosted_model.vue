<script>
import { s__ } from '~/locale';
import { INSTANCE_MODEL_SELECTION_ROUTE_NAMES } from 'ee/ai/instance_model_selection/constants';
import selfHostedModelCreateMutation from '../graphql/mutations/create_self_hosted_model.mutation.graphql';
import { SELF_HOSTED_MODEL_MUTATIONS } from '../constants';
import SelfHostedModelForm from './self_hosted_model_form.vue';

export default {
  name: 'NewSelfHostedModel',
  components: {
    SelfHostedModelForm,
  },
  beforeRouteEnter(to, from, next) {
    next((vm) => {
      if (from.name === INSTANCE_MODEL_SELECTION_ROUTE_NAMES.MODELS) {
        // eslint-disable-next-line no-param-reassign
        vm.cancelRouteName = from.name;
      }
    });
  },
  data() {
    return {
      cancelRouteName: null,
    };
  },
  i18n: {
    title: s__('AdminSelfHostedModels|Add self-hosted model'),
    description: s__(
      'AdminSelfHostedModels|Add a new AI model that can be used for GitLab Duo self-hosted features.',
    ),
  },
  mutationData: {
    name: SELF_HOSTED_MODEL_MUTATIONS.CREATE,
    mutation: selfHostedModelCreateMutation,
  },
};
</script>
<template>
  <div>
    <h1 class="gl-heading-1 gl-m-0">{{ $options.i18n.title }}</h1>
    <p class="gl-pb-2 gl-pt-3">
      {{ $options.i18n.description }}
    </p>
    <self-hosted-model-form
      :mutation-data="$options.mutationData"
      :cancel-route-name="cancelRouteName"
    />
  </div>
</template>
