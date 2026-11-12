<script>
import { GlIcon, GlTooltipDirective } from '@gitlab/ui';
import { titleInLinkSafeHtmlConfig } from '~/lib/dompurify';
import SafeHtml from '~/vue_shared/directives/safe_html';
import TooltipOnTruncate from '~/vue_shared/directives/tooltip_on_truncate';
import { TITLE_LENGTH_MAX } from '~/issues/constants';
import { visitUrl } from '~/lib/utils/url_utility';
import WorkItemTypeIcon from '~/work_items/components/work_item_type_icon.vue';
import CellTextEditor from './editable_cell/cell_text_editor.vue';
import WorkItemEditableCell from './editable_cell/work_item_editable_cell.vue';

export default {
  name: 'WorkItemTitleCell',
  components: {
    CellTextEditor,
    GlIcon,
    WorkItemEditableCell,
    WorkItemTypeIcon,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
    SafeHtml,
    TooltipOnTruncate,
  },
  inject: {
    getWorkItemTypeConfiguration: {
      default: null,
    },
  },
  props: {
    item: {
      type: Object,
      required: true,
    },
    isActive: {
      type: Boolean,
      required: false,
      default: false,
    },
    detailPanelEnabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['set-active-item'],
  computed: {
    workItemType() {
      return this.item.workItemType?.name;
    },
    workItemConfig() {
      return this.getWorkItemTypeConfiguration
        ? this.getWorkItemTypeConfiguration(this.workItemType)
        : {};
    },
    useIssueView() {
      return this.workItemConfig?.useIssueView;
    },
  },
  methods: {
    handleTitleClick(event) {
      if (event.metaKey || event.ctrlKey || event.shiftKey) {
        return;
      }

      event.preventDefault();

      // When detail panel is disabled (bulk edit mode or unsupported view), do nothing on regular click
      // The link's href will work for modifier-key clicks (cmd+click, ctrl+click, middle-click)
      if (!this.detailPanelEnabled) {
        return;
      }

      // Unsupported types (incidents, tickets, test cases) should navigate instead of opening drawer
      if (this.useIssueView) {
        visitUrl(this.item.webPath);
        return;
      }

      this.$emit('set-active-item', this.isActive ? null : this.item);
    },
    isValidTitle(title) {
      return title.trim().length > 0 && title.length <= TITLE_LENGTH_MAX;
    },
    titleInput(editedValue) {
      const title = editedValue.trim();
      return title === this.item.title ? null : { title };
    },
  },
  TITLE_LENGTH_MAX,
  titleInLinkSafeHtmlConfig,
};
</script>

<template>
  <work-item-editable-cell
    :item="item"
    :edit-label="s__('WorkItem|Edit title')"
    :saving-text="s__('WorkItem|Saving title')"
    :error-message="s__('WorkItem|Something went wrong while updating the title.')"
    class="gl-cursor-pointer"
    @cell-click="handleTitleClick"
  >
    <template #prefix>
      <work-item-type-icon
        v-if="item.workItemType"
        :work-item-type="item.workItemType.name"
        :type-icon-name="item.workItemType.iconName"
        icon-variant="subtle"
        class="gl-shrink-0"
      />
      <gl-icon
        v-if="item.confidential"
        v-gl-tooltip
        :title="__('Confidential')"
        :aria-label="__('Confidential')"
        name="eye-slash"
        variant="warning"
        class="gl-shrink-0"
        data-testid="confidential-icon"
      />
    </template>

    <template #display>
      <a
        :href="item.webPath"
        class="gl-min-w-0 gl-font-bold gl-text-default hover:gl-text-default"
        data-testid="work-item-link"
        @click.stop="handleTitleClick"
      >
        <span
          v-safe-html:[$options.titleInLinkSafeHtmlConfig]="item.titleHtml"
          v-tooltip-on-truncate="item.title"
          dir="auto"
          class="gl-block gl-truncate"
          data-testid="work-item-title"
        ></span>
      </a>
    </template>

    <template #editor="{ save, cancel, isSaving }">
      <cell-text-editor
        :value="item.title"
        :is-saving="isSaving"
        :validator="isValidTitle"
        :maxlength="$options.TITLE_LENGTH_MAX"
        @submit="save(titleInput($event))"
        @cancel="cancel"
      />
    </template>
  </work-item-editable-cell>
</template>
