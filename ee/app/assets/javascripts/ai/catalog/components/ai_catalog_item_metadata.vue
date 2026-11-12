<script>
import {
  GlAttributeList,
  GlBadge,
  GlIcon,
  GlLink,
  GlSprintf,
  GlTooltipDirective,
} from '@gitlab/ui';
import AiCatalogItemUserAttribution from 'ee/ai/catalog/components/ai_catalog_item_user_attribution.vue';
import { s__ } from '~/locale';
import { getByVersionKey, isGitLabMaintainedItem } from 'ee/ai/catalog/utils';
import {
  AGENT_VISIBILITY_LEVEL_DESCRIPTIONS,
  AI_CATALOG_TYPE_FLOW,
  AI_CATALOG_TYPE_THIRD_PARTY_FLOW,
  FLOW_VISIBILITY_LEVEL_DESCRIPTIONS,
  VISIBILITY_LEVEL_BADGE_VARIANT,
  VISIBILITY_LEVEL_LABELS,
  VISIBILITY_TYPE_ICON,
} from '../constants';

export default {
  name: 'AiCatalogItemMetadata',
  components: {
    AiCatalogItemUserAttribution,
    GlAttributeList,
    GlBadge,
    GlIcon,
    GlLink,
    GlSprintf,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
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
    activeVersion() {
      return getByVersionKey(this.item, this.versionKey);
    },
    isGitLabMaintained() {
      return isGitLabMaintainedItem(this.item);
    },
    visibilityDescriptions() {
      return this.item.itemType === AI_CATALOG_TYPE_FLOW
        ? FLOW_VISIBILITY_LEVEL_DESCRIPTIONS
        : AGENT_VISIBILITY_LEVEL_DESCRIPTIONS;
    },
    metaData() {
      const items = [];

      if (this.item.visibility) {
        items.push({
          icon: VISIBILITY_TYPE_ICON[this.item.visibility],
          text: VISIBILITY_LEVEL_LABELS[this.item.visibility],
          badgeVariant: VISIBILITY_LEVEL_BADGE_VARIANT[this.item.visibility],
          tooltip: this.visibilityDescriptions[this.item.visibility],
          testId: 'visibility',
        });
      }

      if (this.isGitLabMaintained) {
        items.push({
          icon: 'tanuki-verified',
          text: s__('AICatalog|GitLab-managed'),
          testId: 'gitlab-maintained',
        });
      }

      if (this.item.itemType === AI_CATALOG_TYPE_THIRD_PARTY_FLOW) {
        items.push({
          icon: 'connected',
          text: s__('AICatalog|External'),
          tooltip: s__('AICatalog|Connects to an AI model provider outside GitLab.'),
          testId: 'external',
        });
      }

      if (this.activeVersion?.humanVersionName) {
        items.push({
          icon: 'tag',
          text: this.activeVersion?.humanVersionName,
          testId: 'version',
        });
      }

      if (this.item.last30DayUsageCount !== undefined) {
        items.push({
          icon: 'chart',
          text: this.item.last30DayUsageCount,
          testId: 'usage-count',
          tooltip: s__(
            'AICatalog|The number of projects that have used this item in the last 30 days.',
          ),
        });
      }

      return items;
    },
    managedByProject() {
      return this.isGitLabMaintained ? null : this.item.project;
    },
  },
  sections: [{ label: s__('AICatalog|About'), text: '' }],
};
</script>

<template>
  <div class="gl-@container">
    <gl-attribute-list
      :items="$options.sections"
      layout="vertical"
      class="gl-mb-0 [&_.gl-attribute-list-item:last-child]:gl-border-b-0 [&_.gl-attribute-list-item]:gl-py-0"
    >
      <template #description>
        <ul class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-3 gl-pl-0">
          <li v-for="meta in metaData" :key="meta.testId">
            <span
              v-gl-tooltip="meta.tooltip"
              :tabindex="meta.tooltip ? 0 : null"
              class="gl-inline-flex gl-items-center gl-gap-2"
              :data-testid="`metadata-${meta.testId}`"
            >
              <gl-badge v-if="meta.badgeVariant" :icon="meta.icon" :variant="meta.badgeVariant">
                {{ meta.text }}
              </gl-badge>
              <template v-else>
                <gl-icon :name="meta.icon" variant="subtle" />
                {{ meta.text }}
              </template>
            </span>
          </li>
          <li>
            <ai-catalog-item-user-attribution :item="item" :version-key="versionKey" />
          </li>
          <li
            v-if="managedByProject"
            class="gl-flex gl-items-start gl-gap-2"
            data-testid="metadata-managed-by"
          >
            <gl-icon name="project" variant="subtle" class="gl-mt-1 gl-shrink-0" />
            <span class="gl-min-w-0 gl-break-words">
              <gl-sprintf :message="s__('AICatalog|Managed by %{project}')">
                <template #project>
                  <gl-link :href="managedByProject.webPath">
                    {{ managedByProject.nameWithNamespace }}
                  </gl-link>
                </template>
              </gl-sprintf>
            </span>
          </li>
        </ul>
      </template>
    </gl-attribute-list>
  </div>
</template>
