<script>
import { GlEmptyState, GlLoadingIcon, GlToastMixin } from '@gitlab/ui';
import emptySearchSvg from '@gitlab/svgs/dist/illustrations/empty-state/empty-search-md.svg';
import { s__ } from '~/locale';
import { createAlert } from '~/alert';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { TYPENAME_AI_FLOW_TRIGGER } from 'ee/graphql_shared/constants';
import { getPreviousRoute } from 'ee/ai/duo_agents_platform/router/utils';
import { FLOW_TRIGGERS_INDEX_ROUTE } from 'ee/ai/duo_agents_platform/router/constants';
import { AI_CATALOG_FLOWS_SHOW_ROUTE } from 'ee/ai/catalog/router/constants';
import { AI_CATALOG_TYPE_THIRD_PARTY_FLOW } from 'ee/ai/catalog/constants';
import aiCatalogFlowQuery from 'ee/ai/catalog/graphql/queries/ai_catalog_flow.query.graphql';
import updateAiFlowTriggerMutation from 'ee/ai/duo_agents_platform/graphql/mutations/update_ai_flow_trigger.mutation.graphql';
import getAiFlowTriggersQuery from 'ee/ai/duo_agents_platform/graphql/queries/get_ai_flow_triggers.query.graphql';
import FlowTriggerForm from './components/flow_trigger_form.vue';

const toInitialValues = (flowTrigger, aiCatalogItemConsumer) => ({
  description: flowTrigger.description,
  eventTypes: flowTrigger.eventTypes,
  user: flowTrigger.user,
  configPath: flowTrigger.configPath,
  filter: flowTrigger.filter || {},
  goals: flowTrigger.goals || {},
  statusOnFinish: flowTrigger.statusOnFinish ?? null,
  readyMergeRequestsOnFinish: Boolean(flowTrigger.readyMergeRequestsOnFinish),
  aiCatalogItemConsumer,
});

export default {
  name: 'FlowTriggersEdit',
  components: {
    FlowTriggerForm,
    GlEmptyState,
    GlLoadingIcon,
    PageHeading,
  },
  mixins: [GlToastMixin, glFeatureFlagsMixin()],
  inject: {
    projectPath: { default: null },
    projectId: { default: null },
    isGroupNamespace: { default: false },
  },
  props: {
    // Provided by the parent flow route in a group, where triggers can't be queried by ID.
    aiCatalogItem: {
      type: Object,
      required: false,
      default: null,
    },
  },
  data() {
    return {
      flowTrigger: {},
      errorMessages: [],
      isLoadingMutation: false,
    };
  },
  apollo: {
    flowTrigger: {
      query: getAiFlowTriggersQuery,
      variables() {
        return {
          projectPath: this.projectPath,
          ids: [this.flowTriggerGraphQlId],
        };
      },
      skip() {
        return this.isGroupNamespace;
      },
      update(data) {
        const flowTrigger = data.project?.aiFlowTriggers?.nodes[0];
        return flowTrigger
          ? toInitialValues(flowTrigger, {
              id: flowTrigger?.aiCatalogItemConsumer?.id,
              name: flowTrigger?.aiCatalogItemConsumer?.item.name,
            })
          : {};
      },
      error(error) {
        createAlert({
          message: error.message,
          captureError: true,
        });
      },
    },
  },
  computed: {
    isQueryLoading() {
      return this.$apollo.queries.flowTrigger.loading;
    },
    flowTriggerGraphQlId() {
      const id = this.isGroupNamespace ? this.$route.params.triggerId : this.$route.params.id;
      return convertToGraphQLId(TYPENAME_AI_FLOW_TRIGGER, id);
    },
    groupFlowTrigger() {
      const configuration = this.aiCatalogItem?.configurationForGroup;
      const flowTrigger = configuration?.flowTriggers?.find(
        ({ id }) => id === this.flowTriggerGraphQlId,
      );
      return flowTrigger
        ? toInitialValues(flowTrigger, { id: configuration.id, name: this.aiCatalogItem.name })
        : {};
    },
    groupCatalogItem() {
      if (!this.isGroupNamespace || !this.aiCatalogItem) return null;

      const configuration = this.aiCatalogItem.configurationForGroup;
      return {
        id: configuration?.id,
        name: this.aiCatalogItem.name,
        isExternalAgent: this.aiCatalogItem.itemType === AI_CATALOG_TYPE_THIRD_PARTY_FLOW,
        acceptsTriggerGoal: Boolean(this.aiCatalogItem.acceptsTriggerGoal),
        foundational: Boolean(this.aiCatalogItem.foundationalFlowReference),
        serviceAccountId: configuration?.serviceAccount?.id ?? null,
      };
    },
    currentFlowTrigger() {
      return this.isGroupNamespace ? this.groupFlowTrigger : this.flowTrigger;
    },
    isNotFound() {
      return this.currentFlowTrigger && Object.keys(this.currentFlowTrigger).length === 0;
    },
  },
  methods: {
    goToPreviousRoute() {
      const previousRoute = getPreviousRoute();
      if (previousRoute) {
        this.$router.push(previousRoute);
      } else if (this.isGroupNamespace) {
        this.$router.push({
          name: AI_CATALOG_FLOWS_SHOW_ROUTE,
          params: { id: this.$route.params.id },
        });
      } else {
        this.$router.push({ name: FLOW_TRIGGERS_INDEX_ROUTE });
      }
    },
    async updateAiFlowTrigger(input) {
      this.resetErrorMessages();
      this.isLoadingMutation = true;

      try {
        const {
          data: {
            aiFlowTriggerUpdate: { errors },
          },
        } = await this.$apollo.mutate({
          mutation: updateAiFlowTriggerMutation,
          variables: {
            input: {
              ...input,
              id: this.flowTriggerGraphQlId,
            },
          },
          refetchQueries: this.isGroupNamespace ? [aiCatalogFlowQuery] : [],
          awaitRefetchQueries: this.isGroupNamespace,
        });

        if (errors.length > 0) {
          this.errorMessages = errors;
          return;
        }

        this.$toast.show(
          this.glFeatures.duoAutomations
            ? s__('DuoAgentsPlatform|Automation updated successfully.')
            : s__('DuoAgentsPlatform|Trigger updated successfully.'),
        );
        this.goToPreviousRoute();
      } catch (error) {
        this.errorMessages = [
          error.message ||
            (this.glFeatures.duoAutomations
              ? s__('DuoAgentsPlatform|The automation could not be updated. Try again.')
              : s__('DuoAgentsPlatform|The trigger could not be updated. Try again.')),
        ];
      } finally {
        this.isLoadingMutation = false;
      }
    },
    resetErrorMessages() {
      this.errorMessages = [];
    },
  },
  emptySearchSvg,
};
</script>

<template>
  <div class="gl-mx-auto @lg/panel:gl-w-2/3">
    <page-heading
      :heading="
        glFeatures.duoAutomations
          ? s__('DuoAgentsPlatform|Edit automation')
          : s__('DuoAgentsPlatform|Edit trigger')
      "
    >
      <template #description>
        {{
          glFeatures.duoAutomations
            ? s__('DuoAgentsPlatform|Change the target or events for this automation.')
            : s__('DuoAgentsPlatform|Change the target or events for this trigger.')
        }}
      </template>
    </page-heading>
    <gl-loading-icon v-if="isQueryLoading" size="lg" class="gl-my-5" />
    <gl-empty-state
      v-else-if="isNotFound"
      :title="
        glFeatures.duoAutomations
          ? s__('DuoAgentsPlatform|Automation not found.')
          : s__('DuoAgentsPlatform|Trigger not found.')
      "
      :svg-path="$options.emptySearchSvg"
    />
    <flow-trigger-form
      v-else
      :error-messages="errorMessages"
      :project-path="projectPath"
      :project-id="projectId"
      :is-loading="isLoadingMutation"
      :initial-values="currentFlowTrigger"
      :group-catalog-item="groupCatalogItem"
      mode="edit"
      @cancel="goToPreviousRoute"
      @dismiss-errors="resetErrorMessages"
      @submit="updateAiFlowTrigger"
    />
  </div>
</template>
