<script>
import { FOUNDATIONAL_FLOW_REFERENCE_CODE_REVIEW } from '../constants';
import { getByVersionKey } from '../utils';
import AiCatalogItemField from './ai_catalog_item_field.vue';
import AiCatalogItemFieldServiceAccount from './ai_catalog_item_field_service_account.vue';
import TriggerField from './trigger_field.vue';
import FormFlowDefinition from './form_flow_definition.vue';
import FormSection from './form_section.vue';

export default {
  name: 'AiCatalogFlowDetails',
  components: {
    AiCatalogItemField,
    AiCatalogItemFieldServiceAccount,
    FormFlowDefinition,
    FormSection,
    TriggerField,
  },
  inject: {
    isGroupNamespace: { default: false },
  },
  props: {
    item: {
      type: Object,
      required: true,
    },
    versionKey: {
      type: String,
      required: true,
    },
  },
  computed: {
    hasProjectConfiguration() {
      return Boolean(this.item.configurationForProject);
    },
    hasGroupConfiguration() {
      return Boolean(this.item.configurationForGroup);
    },
    // Project pages also fetch the root group's configuration, but its triggers are only
    // manageable from the group.
    hasConsumerConfiguration() {
      return this.hasProjectConfiguration || (this.isGroupNamespace && this.hasGroupConfiguration);
    },
    definition() {
      return getByVersionKey(this.item, this.versionKey).definition;
    },
    serviceAccount() {
      if (this.hasProjectConfiguration && !this.item.foundational) {
        return this.item.configurationForProject?.flowTriggers?.[0]?.user;
      }
      return this.item.configurationForGroup?.serviceAccount;
    },
    isCodeReviewFoundational() {
      return (
        this.item.foundational &&
        this.item.foundationalFlowReference === FOUNDATIONAL_FLOW_REFERENCE_CODE_REVIEW
      );
    },
    hasConfigurationContent() {
      if (this.isCodeReviewFoundational) return false;
      return Boolean(this.hasConsumerConfiguration || !this.item.foundational);
    },
  },
};
</script>

<template>
  <div v-if="hasConfigurationContent || serviceAccount">
    <h2 class="gl-heading-3 gl-mb-4 gl-mt-0 gl-font-semibold">
      {{ s__('AICatalog|Flow configuration') }}
    </h2>
    <div class="gl-flex gl-flex-col gl-gap-7">
      <form-section v-if="hasConfigurationContent" is-display data-testid="configuration-section">
        <trigger-field v-if="hasConsumerConfiguration" :item="item" />
        <ai-catalog-item-field
          v-if="!item.foundational"
          :title="s__('AICatalog|YAML configuration')"
          data-testid="configuration-field"
        >
          <form-flow-definition :value="definition" read-only class="gl-mt-3" />
        </ai-catalog-item-field>
      </form-section>
      <form-section v-if="serviceAccount" :title="s__('AICatalog|Service account')" is-display>
        <ai-catalog-item-field-service-account
          :service-account="serviceAccount"
          :item-type="item.itemType"
          :foundational-flow-reference="item.foundationalFlowReference"
          data-testid="service-account-field"
        />
      </form-section>
    </div>
  </div>
</template>
