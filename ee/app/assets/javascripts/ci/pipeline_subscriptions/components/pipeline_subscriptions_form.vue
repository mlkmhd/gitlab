<script>
import { GlButton, GlForm, GlFormGroup, GlFormInput, GlLink } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import { s__ } from '~/locale';
import { createAlert } from '~/alert';
import HelpIcon from '~/vue_shared/components/help_icon/help_icon.vue';
import AddPipelineSubscription from '../graphql/mutations/add_pipeline_subscription.mutation.graphql';

export default {
  name: 'PipelineSubscriptionsForm',
  docsLink: helpPagePath('ci/pipelines/_index', {
    anchor: 'trigger-a-pipeline-when-an-upstream-project-is-rebuilt',
  }),
  components: {
    GlButton,
    GlForm,
    GlFormGroup,
    GlFormInput,
    GlLink,
    HelpIcon,
  },
  inject: {
    projectPath: {
      default: '',
    },
  },
  emits: ['add-subscription-success', 'canceled'],
  data() {
    return {
      upstreamPath: '',
    };
  },
  methods: {
    async createSubscription() {
      try {
        const { data } = await this.$apollo.mutate({
          mutation: AddPipelineSubscription,
          variables: {
            input: {
              projectPath: this.projectPath,
              upstreamPath: this.upstreamPath,
            },
          },
        });

        if (data.projectSubscriptionCreate.errors.length > 0) {
          createAlert({ message: data.projectSubscriptionCreate.errors[0] });
        } else {
          createAlert({
            message: s__('PipelineSubscriptions|Subscription successfully created.'),
            variant: 'success',
          });
          this.upstreamPath = '';

          this.$emit('add-subscription-success');
        }
      } catch (error) {
        const { graphQLErrors } = error;

        if (graphQLErrors.length > 0) {
          createAlert({ message: graphQLErrors[0]?.message, variant: 'warning' });
        } else {
          createAlert({
            message: s__(
              'PipelineSubscriptions|An error occurred while adding a new pipeline subscription.',
            ),
          });
        }
      }
    },
    cancelSubscription() {
      this.upstreamPath = '';
      this.$emit('canceled');
    },
  },
};
</script>

<template>
  <div>
    <h4 class="gl-mt-0">{{ s__('PipelineSubscriptions|Add new pipeline subscription') }}</h4>
    <gl-form>
      <gl-form-group label-for="project-path">
        <template #label>
          {{ __('Project path') }}
          <gl-link :href="$options.docsLink" target="_blank">
            <help-icon />
          </gl-link>
        </template>
        <gl-form-input
          id="project-path"
          v-model="upstreamPath"
          type="text"
          :placeholder="__('Paste project path (i.e. gitlab-org/gitlab)')"
          data-testid="upstream-project-path-field"
        />
      </gl-form-group>

      <div class="gl-flex gl-gap-3">
        <gl-button variant="confirm" data-testid="subscribe-button" @click="createSubscription">
          {{ __('Subscribe') }}
        </gl-button>
        <gl-button data-testid="cancel-button" @click="cancelSubscription">
          {{ __('Cancel') }}
        </gl-button>
      </div>
    </gl-form>
  </div>
</template>
