<script>
import {
  GlAvatar,
  GlAvatarLink,
  GlAvatarsInline,
  GlLink,
  GlToastMixin,
  GlTooltipDirective,
  GlTruncate,
} from '@gitlab/ui';
import { xor } from 'lodash-es';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { __, n__, s__ } from '~/locale';
import { userIsDisabled } from '~/ai/agents_utils';
import { FLOW_TRIGGER_EVENTS } from '~/vue_shared/constants';
import usersSearchQuery from '~/graphql_shared/queries/workspace_autocomplete_users.query.graphql';
import SidebarParticipant from '~/sidebar/components/assignees/sidebar_participant.vue';
import workItemEditMetadataQuery from '../graphql/work_item_edit_metadata.query.graphql';
import { findAssigneesWidget } from '../../utils';
import { EDIT_TRIGGER_CELL } from '../constants';
import CellListboxEditor from './editable_cell/cell_listbox_editor.vue';
import WorkItemEditableCell from './editable_cell/work_item_editable_cell.vue';

const MAX_VISIBLE_ASSIGNEES = 3;
const AVATAR_SIZE = 16;

const toOption = (user) => ({ ...user, value: user.id, text: user.name });

export default {
  name: 'WorkItemAssigneesCell',
  components: {
    CellListboxEditor,
    GlAvatar,
    GlAvatarLink,
    GlAvatarsInline,
    GlLink,
    GlTruncate,
    SidebarParticipant,
    WorkItemEditableCell,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [GlToastMixin],
  inject: {
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
    users: {
      query: usersSearchQuery,
      variables() {
        return {
          fullPath: this.rootPageFullPath,
          search: this.searchTerm,
          isProject: !this.isGroup,
        };
      },
      // The editor sends its first search when it opens.
      skip() {
        return this.searchTerm === null;
      },
      update(data) {
        const users = (this.isGroup ? data.groupNamespace?.users : data.namespace?.users) ?? [];
        return users.map((user) => toOption(user));
      },
      error() {
        this.$toast.show(s__('WorkItem|Something went wrong when fetching users.'));
      },
    },
    editMetadata: {
      query: workItemEditMetadataQuery,
      variables() {
        return { id: this.item.id };
      },
      skip() {
        return this.searchTerm === null;
      },
      update(data) {
        return data.workItem;
      },
      error(error) {
        Sentry.captureException(error);
      },
    },
  },
  data() {
    return {
      searchTerm: null,
      users: [],
      editMetadata: null,
    };
  },
  computed: {
    assignees() {
      return findAssigneesWidget(this.item)?.assignees?.nodes || [];
    },
    assigneeIds() {
      return this.assignees.map((user) => user.id);
    },
    assigneeOptions() {
      return this.assignees.map((user) => toOption(user));
    },
    // The list response does not include this, so it is fetched when editing starts. Falling back
    // to multi-select is safe: the server keeps only the first assignee when the work item allows one.
    allowsMultipleAssignees() {
      return findAssigneesWidget(this.editMetadata)?.allowsMultipleAssignees ?? true;
    },
    isLoading() {
      return this.$apollo.queries.users.loading || this.$apollo.queries.editMetadata.loading;
    },
    // Users who cannot be assigned (such as some AI agents) can still be unassigned.
    unassignableUserIds() {
      return this.users
        .filter((user) => userIsDisabled(user, FLOW_TRIGGER_EVENTS.ASSIGN))
        .map((user) => user.id);
    },
    headerText() {
      return this.allowsMultipleAssignees ? __('Select assignees') : __('Select assignee');
    },
  },
  methods: {
    search(term) {
      this.searchTerm = term;
    },
    // Avatars and the name are links to the user, so clicking them should not start editing.
    stopLinkClick(event) {
      if (event.target.closest('a')) event.stopPropagation();
    },
    // Only one assignee is named, since more than one would not fit the column.
    singleAssignee(users) {
      return users.length === 1 ? users[0] : null;
    },
    hiddenAssigneesText(users) {
      const count = users.length - MAX_VISIBLE_ASSIGNEES;
      return n__('%d additional assignee', '%d additional assignees', count);
    },
    async loadEditMetadata() {
      if (this.editMetadata) return;
      try {
        const { data } = await this.$apollo.query({
          query: workItemEditMetadataQuery,
          variables: { id: this.item.id },
        });
        this.editMetadata = data.workItem;
      } catch {
        // The smart query reports the error, and saving falls back to multi-select.
      }
    },
    assigneesInput(selection) {
      const selectedIds = [selection].flat().filter(Boolean);
      // New picks are appended, so a single-assignee item keeps the latest one.
      const assigneeIds = this.allowsMultipleAssignees ? selectedIds : selectedIds.slice(-1);

      if (!xor(assigneeIds, this.assigneeIds).length) return null;
      return { assigneesWidget: { assigneeIds } };
    },
    // The listbox has closed by now, so the cell leaves edit mode whether or not the save worked.
    async submit(selection, { save, cancel }) {
      await this.loadEditMetadata();
      await save(this.assigneesInput(selection));
      cancel();
      this.search('');
    },
  },
  AVATAR_SIZE,
  EDIT_TRIGGER_CELL,
  MAX_VISIBLE_ASSIGNEES,
};
</script>

<template>
  <work-item-editable-cell
    :item="item"
    :edit-trigger="$options.EDIT_TRIGGER_CELL"
    :error-message="s__('WorkItem|Something went wrong while updating the assignees.')"
    class="gl-w-full gl-overflow-hidden gl-px-4 gl-py-3"
    data-testid="cell-assignees"
  >
    <template #display>
      <span
        class="gl-flex gl-min-w-0 gl-items-center gl-gap-2"
        :class="{ 'gl-h-5': !assignees.length }"
        @click="stopLinkClick"
      >
        <gl-avatars-inline
          v-if="assignees.length"
          :avatars="assignees"
          :avatar-size="$options.AVATAR_SIZE"
          :max-visible="$options.MAX_VISIBLE_ASSIGNEES"
          :badge-sr-only-text="hiddenAssigneesText(assignees)"
          badge-tooltip-prop="name"
          collapsed
          class="avatars-inline-compact gl-shrink-0"
          data-testid="assignee-avatars"
        >
          <template #avatar="{ avatar }">
            <gl-avatar-link v-gl-tooltip :href="avatar.webPath" :title="avatar.name">
              <gl-avatar :src="avatar.avatarUrl" :alt="avatar.name" :size="$options.AVATAR_SIZE" />
            </gl-avatar-link>
          </template>
        </gl-avatars-inline>
        <gl-link
          v-if="singleAssignee(assignees)"
          :href="singleAssignee(assignees).webPath"
          class="gl-group gl-min-w-0 gl-text-default hover:gl-text-default"
          data-testid="assignee-name-link"
        >
          <!-- The link's own underline does not reach into GlTruncate's inline-flex root -->
          <gl-truncate :text="singleAssignee(assignees).name" class="group-hover:gl-underline" />
        </gl-link>
      </span>
    </template>

    <template #editor="editor">
      <cell-listbox-editor
        :items="users"
        :selected-options="assigneeOptions"
        :multiple="allowsMultipleAssignees"
        :unselectable-values="unassignableUserIds"
        :searching="isLoading"
        :is-saving="editor.isSaving"
        :header-text="headerText"
        :reset-button-label="s__('WorkItem|Clear')"
        :no-results-text="s__('WorkItem|No matching results')"
        data-testid="assignees-listbox"
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
            <gl-avatars-inline
              v-if="pickedOptions.length"
              :avatars="pickedOptions"
              :avatar-size="$options.AVATAR_SIZE"
              :max-visible="$options.MAX_VISIBLE_ASSIGNEES"
              :badge-sr-only-text="hiddenAssigneesText(pickedOptions)"
              badge-tooltip-prop="name"
              collapsed
              class="avatars-inline-compact gl-shrink-0"
              data-testid="toggle-assignees"
            >
              <template #avatar="{ avatar }">
                <gl-avatar
                  v-gl-tooltip
                  :src="avatar.avatarUrl"
                  :alt="avatar.name"
                  :title="avatar.name"
                  :size="$options.AVATAR_SIZE"
                />
              </template>
            </gl-avatars-inline>
            <gl-truncate
              v-if="singleAssignee(pickedOptions)"
              :text="singleAssignee(pickedOptions).name"
            />
          </div>
        </template>
        <template #list-item="{ item: user }">
          <sidebar-participant :user="user" />
        </template>
      </cell-listbox-editor>
    </template>
  </work-item-editable-cell>
</template>
