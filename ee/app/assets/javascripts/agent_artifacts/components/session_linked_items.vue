<script>
import { GlIcon, GlLink, GlSprintf } from '@gitlab/ui';
import { __, s__ } from '~/locale';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import WorkItemTypeIcon from '~/work_items/components/work_item_type_icon.vue';

const KIND_ICONS = {
  mergeRequest: 'git-merge',
  note: 'comment',
};

export default {
  name: 'SessionLinkedItems',
  components: {
    GlIcon,
    GlLink,
    GlSprintf,
    CrudComponent,
    WorkItemTypeIcon,
  },
  props: {
    startedFrom: {
      type: Array,
      required: false,
      default: () => [],
    },
    created: {
      type: Array,
      required: false,
      default: () => [],
    },
    hasMore: {
      type: Boolean,
      required: false,
      default: false,
    },
    sessionPath: {
      type: String,
      required: false,
      default: null,
    },
  },
  computed: {
    groups() {
      return [
        {
          key: 'source',
          title: __('Source'),
          items: this.startedFrom,
        },
        {
          key: 'created',
          title: s__('AgentArtifacts|Created'),
          items: this.created,
        },
      ].filter(({ items }) => items.length > 0);
    },
  },
  kindIcons: KIND_ICONS,
  i18n: {
    moreLinkedItems: s__('AgentArtifacts|Some linked items are not shown.'),
    moreLinkedItemsWithLink: s__(
      'AgentArtifacts|Some linked items are not shown. %{linkStart}View full session details%{linkEnd}',
    ),
  },
};
</script>

<template>
  <crud-component :title="s__('AgentArtifacts|Linked items')" is-collapsible>
    <div class="gl-flex gl-flex-col gl-gap-5">
      <section v-for="group in groups" :key="group.key" :data-testid="`linked-items-${group.key}`">
        <h5 class="gl-mb-3 gl-mt-0">{{ group.title }}</h5>
        <ul class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-3 gl-p-0">
          <li
            v-for="item in group.items"
            :key="item.id"
            class="gl-flex gl-items-center gl-gap-2"
            data-testid="linked-item"
          >
            <work-item-type-icon
              v-if="item.kind === 'workItem'"
              :work-item-type="item.workItemType.name || ''"
              :type-icon-name="item.workItemType.iconName || ''"
            />
            <gl-icon v-else :name="$options.kindIcons[item.kind]" variant="subtle" />
            <gl-link
              :href="item.url"
              class="gl-min-w-0 gl-break-words"
              data-testid="linked-item-link"
            >
              {{ item.title }}
            </gl-link>
            <span v-if="item.reference" class="gl-shrink-0 gl-text-subtle">{{
              item.reference
            }}</span>
          </li>
        </ul>
      </section>
      <p v-if="hasMore" class="gl-m-0 gl-text-subtle" data-testid="linked-items-more">
        <gl-sprintf v-if="sessionPath" :message="$options.i18n.moreLinkedItemsWithLink">
          <template #link="{ content }">
            <gl-link :href="sessionPath" data-testid="linked-items-more-link">{{
              content
            }}</gl-link>
          </template>
        </gl-sprintf>
        <template v-else>{{ $options.i18n.moreLinkedItems }}</template>
      </p>
    </div>
  </crud-component>
</template>
