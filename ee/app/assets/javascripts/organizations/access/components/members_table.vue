<script>
import {
  GlAvatarLabeled,
  GlAvatarLink,
  GlButton,
  GlDisclosureDropdown,
  GlEmptyState,
  GlLoadingIcon,
  GlTableLite,
  GlTooltipDirective,
} from '@gitlab/ui';
import { __, s__ } from '~/locale';
import CreatedAt from '~/members/components/table/created_at.vue';

const ACTION_EVENTS = {
  'edit-role': 'select-member',
  'remove-member': 'remove-member',
  leave: 'leave',
};

export default {
  name: 'OrganizationAccessMembersTable',
  components: {
    CreatedAt,
    GlAvatarLabeled,
    GlAvatarLink,
    GlButton,
    GlDisclosureDropdown,
    GlEmptyState,
    GlLoadingIcon,
    GlTableLite,
  },
  directives: { GlTooltip: GlTooltipDirective },
  props: {
    resource: {
      type: Object,
      required: true,
    },
    members: {
      type: Array,
      required: true,
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
    hasActiveFilters: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['select-member', 'remove-member', 'leave'],
  computed: {
    emptyState() {
      if (this.hasActiveFilters) return this.$options.emptyStates.noResults;

      return {
        illustration: 'empty-user-md',
        title: s__('OrganizationAccess|Grant access to members'),
        description: this.resource.noMembersDescription,
      };
    },
    roleLabels() {
      return Object.fromEntries(this.resource.roles.map(({ value, text }) => [value, text]));
    },
  },
  methods: {
    canUpdateRole({ userPermissions }) {
      return Boolean(userPermissions?.updateRole);
    },
    // A null or unknown role is a platform grant, such as the owner sync's organization_admin.
    // assignedRole from https://gitlab.com/gitlab-org/gitlab/-/merge_requests/267558 will name it.
    memberRole({ role }) {
      const label = this.roleLabels[role];

      if (label) return { label, isOrganization: false };

      return {
        label: s__('OrganizationAccess|Organization role'),
        isOrganization: true,
      };
    },
    rowActions({ userPermissions }) {
      const { editRole, removeMember, leave } = this.$options.actions;
      const permissions = userPermissions ?? {};
      return [
        permissions.updateRole && editRole,
        permissions.removeMember && removeMember,
        permissions.leave && leave,
      ].filter(Boolean);
    },
    onAction({ key }, member) {
      this.$emit(ACTION_EVENTS[key], member);
    },
  },
  actions: {
    editRole: { key: 'edit-role', text: s__('OrganizationAccess|Edit role') },
    removeMember: {
      key: 'remove-member',
      text: s__('OrganizationAccess|Remove member'),
      variant: 'danger',
    },
    leave: { key: 'leave', text: __('Leave'), variant: 'danger' },
  },
  fields: [
    { key: 'member', label: s__('OrganizationAccess|Member') },
    { key: 'role', label: s__('OrganizationAccess|Role') },
    { key: 'granted', label: s__('OrganizationAccess|Access granted') },
    {
      key: 'actions',
      label: __('Actions'),
      thClass: 'gl-sr-only',
      tdClass: '@md/panel:gl-text-right',
    },
  ],
  emptyStates: {
    noResults: {
      illustration: 'empty-search-md',
      title: s__('OrganizationAccess|No results found'),
      description: s__('OrganizationAccess|Edit your search and try again.'),
    },
  },
  avatarSize: 32,
};
</script>

<template>
  <gl-loading-icon v-if="loading" size="lg" class="gl-mt-5" />
  <gl-empty-state
    v-else-if="!members.length"
    :illustration-name="emptyState.illustration"
    :title="emptyState.title"
    :description="emptyState.description"
    data-testid="members-empty"
  />
  <!-- Without a row key, rows are reused by index, and Vue 3 keeps the old row's click handler. -->
  <gl-table-lite
    v-else
    :items="members"
    :fields="$options.fields"
    primary-key="assignee.id"
    stacked="md"
  >
    <template #cell(member)="{ item }">
      <gl-avatar-link :href="item.assignee.webPath" data-testid="member-avatar-link">
        <gl-avatar-labeled
          :size="$options.avatarSize"
          :src="item.assignee.avatarUrl"
          :entity-name="item.assignee.name"
          :label="item.assignee.name"
          :sub-label="`@${item.assignee.username}`"
        />
      </gl-avatar-link>
    </template>

    <template #cell(role)="{ item }">
      <gl-button
        v-if="canUpdateRole(item) && !memberRole(item).isOrganization"
        variant="link"
        data-testid="member-role-button"
        @click="$emit('select-member', item)"
      >
        {{ memberRole(item).label }}
      </gl-button>
      <span v-else data-testid="member-role-text">{{ memberRole(item).label }}</span>
    </template>

    <template #cell(granted)="{ item }">
      <created-at :date="item.createdAt" />
    </template>

    <template #cell(actions)="{ item }">
      <gl-disclosure-dropdown
        v-if="rowActions(item).length"
        v-gl-tooltip="__('Actions')"
        :items="rowActions(item)"
        :toggle-text="__('Actions')"
        text-sr-only
        icon="ellipsis_v"
        category="tertiary"
        no-caret
        placement="bottom-end"
        data-testid="member-actions"
        @action="onAction($event, item)"
      />
    </template>
  </gl-table-lite>
</template>
