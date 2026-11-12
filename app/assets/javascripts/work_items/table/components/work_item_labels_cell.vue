<script>
import { GlLabel, GlPopover, GlToastMixin } from '@gitlab/ui';
import { difference } from 'lodash-es';
import { s__ } from '~/locale';
import { isScopedLabel } from '~/lib/utils/common_utils';
import groupLabelsQuery from '~/sidebar/components/labels/labels_select_widget/graphql/group_labels.query.graphql';
import projectLabelsQuery from '~/sidebar/components/labels/labels_select_widget/graphql/project_labels.query.graphql';
import { findLabelsWidget, formatLabelForListbox } from '../../utils';
import { EDIT_TRIGGER_CELL } from '../constants';
import CellListboxEditor from './editable_cell/cell_listbox_editor.vue';
import WorkItemEditableCell from './editable_cell/work_item_editable_cell.vue';

const MAX_VISIBLE_LABELS = 3;

// The toggle and list items need the label's title, description and colour as well.
const toOption = (label) => ({ ...label, ...formatLabelForListbox(label) });

export default {
  name: 'WorkItemLabelsCell',
  components: {
    CellListboxEditor,
    GlLabel,
    GlPopover,
    WorkItemEditableCell,
  },
  mixins: [GlToastMixin],
  inject: {
    hasScopedLabelsFeature: {
      default: false,
    },
    isGroup: {
      default: false,
    },
    rootPageFullPath: {},
  },
  props: {
    item: {
      type: Object,
      required: true,
    },
  },
  apollo: {
    availableLabels: {
      query() {
        return this.isGroup ? groupLabelsQuery : projectLabelsQuery;
      },
      variables() {
        return {
          fullPath: this.rootPageFullPath,
          searchTerm: this.searchTerm,
        };
      },
      // The editor sends its first search when it opens.
      skip() {
        return this.searchTerm === null;
      },
      update(data) {
        return (data.namespace?.labels?.nodes ?? []).map((label) => toOption(label));
      },
      error() {
        this.$toast.show(s__('WorkItem|Something went wrong when fetching labels.'));
      },
    },
  },
  data() {
    return {
      searchTerm: null,
      availableLabels: [],
    };
  },
  computed: {
    labels() {
      return findLabelsWidget(this.item)?.labels?.nodes || [];
    },
    labelIds() {
      return this.labels.map((label) => label.id);
    },
    labelOptions() {
      return this.labels.map((label) => toOption(label));
    },
    allowsScopedLabels() {
      return Boolean(
        this.hasScopedLabelsFeature || findLabelsWidget(this.item)?.allowsScopedLabels,
      );
    },
    isLoadingLabels() {
      return this.$apollo.queries.availableLabels.loading;
    },
    visibleLabels() {
      return this.labels.slice(0, MAX_VISIBLE_LABELS);
    },
    hiddenLabels() {
      return this.labels.slice(MAX_VISIBLE_LABELS);
    },
  },
  methods: {
    search(term) {
      this.searchTerm = term;
    },
    labelsInput(selectedIds) {
      const addLabelIds = difference(selectedIds, this.labelIds);
      const removeLabelIds = difference(this.labelIds, selectedIds);

      if (!addLabelIds.length && !removeLabelIds.length) return null;
      return { labelsWidget: { addLabelIds, removeLabelIds } };
    },
    // The listbox has closed by now, so the cell leaves edit mode whether or not the save worked.
    async submit(selectedIds, { save, cancel }) {
      await save(this.labelsInput(selectedIds));
      cancel();
      this.search('');
    },
    scopedLabel(label) {
      return this.allowsScopedLabels && isScopedLabel(label);
    },
    labelFilterUrl(label) {
      return `?label_name[]=${encodeURIComponent(label.title)}`;
    },
    moreLabelsText(labels) {
      return `+${labels.length - MAX_VISIBLE_LABELS}`;
    },
  },
  EDIT_TRIGGER_CELL,
  MAX_VISIBLE_LABELS,
};
</script>

<template>
  <work-item-editable-cell
    :item="item"
    :edit-trigger="$options.EDIT_TRIGGER_CELL"
    :error-message="s__('WorkItem|Something went wrong while updating the labels.')"
    class="gl-w-full gl-overflow-hidden gl-px-4 gl-py-3"
  >
    <template #display>
      <span
        class="gl-flex gl-min-w-0 gl-items-center gl-gap-2"
        :class="{ 'gl-h-5': !labels.length }"
      >
        <gl-label
          v-for="label in visibleLabels"
          :key="label.id"
          :background-color="label.color"
          :title="label.title"
          :description="label.description"
          :scoped="scopedLabel(label)"
          :target="labelFilterUrl(label)"
          class="gl-shrink-0"
          data-testid="label-item"
          @click.stop
        />
        <span
          v-if="hiddenLabels.length"
          :id="`more-labels-${item.id}`"
          class="gl-cursor-pointer gl-rounded-pill gl-bg-strong gl-px-3 gl-text-sm"
          data-testid="more-labels-button"
          @click.stop
        >
          {{ moreLabelsText(labels) }}
        </span>
        <gl-popover
          v-if="hiddenLabels.length"
          :target="`more-labels-${item.id}`"
          triggers="hover focus"
          placement="bottom"
        >
          <div class="gl-flex gl-flex-wrap gl-gap-2">
            <gl-label
              v-for="label in hiddenLabels"
              :key="label.id"
              :background-color="label.color"
              :title="label.title"
              :description="label.description"
              :scoped="scopedLabel(label)"
              :target="labelFilterUrl(label)"
              class="gl-shrink-0"
              @click.stop
            />
          </div>
        </gl-popover>
      </span>
    </template>

    <template #editor="editor">
      <cell-listbox-editor
        :items="availableLabels"
        :selected-options="labelOptions"
        :searching="isLoadingLabels"
        :is-saving="editor.isSaving"
        :header-text="s__('WorkItem|Select labels')"
        :reset-button-label="s__('WorkItem|Clear')"
        :no-results-text="s__('WorkItem|No matching results')"
        multiple
        data-testid="labels-listbox"
        @search="search"
        @submit="submit($event, editor)"
      >
        <template #toggle="{ accessibilityAttributes, pickedOptions }">
          <div
            role="button"
            tabindex="0"
            class="gl-flex gl-w-full gl-min-w-0 gl-cursor-pointer gl-items-center gl-gap-2 gl-text-left gl-text-sm"
            v-bind="accessibilityAttributes"
          >
            <gl-label
              v-for="label in pickedOptions.slice(0, $options.MAX_VISIBLE_LABELS)"
              :key="label.id"
              :background-color="label.color"
              :title="label.title"
              :description="label.description"
              :scoped="scopedLabel(label)"
              :target="labelFilterUrl(label)"
              class="gl-shrink-0"
              data-testid="toggle-label-item"
              @click.stop
            />
            <span
              v-if="pickedOptions.length > $options.MAX_VISIBLE_LABELS"
              class="gl-rounded-pill gl-bg-strong gl-px-3 gl-text-sm"
              data-testid="toggle-more-labels"
            >
              {{ moreLabelsText(pickedOptions) }}
            </span>
          </div>
        </template>
        <template #list-item="{ item: label }">
          <div class="gl-flex gl-items-center gl-gap-3">
            <span
              :style="{ background: label.color }"
              class="gl-border gl-h-3 gl-w-5 gl-shrink-0 gl-rounded-base gl-border-white"
            ></span>
            {{ label.text }}
          </div>
        </template>
      </cell-listbox-editor>
    </template>
  </work-item-editable-cell>
</template>
