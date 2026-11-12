<script>
import {
  GlButton,
  GlEmptyState,
  GlFilteredSearch,
  GlFilteredSearchToken,
  GlModalDirective,
} from '@gitlab/ui';
import { createAlert } from '~/alert';
import { TYPENAME_USER } from '~/graphql_shared/constants';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { parseErrorMessage } from '~/lib/utils/error_message';
import { n__, s__, sprintf } from '~/locale';
import { OPERATOR_IS, OPERATORS_IS } from '~/vue_shared/components/filtered_search_bar/constants';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import showGlobalToast from '~/vue_shared/plugins/global_toast';
import { MAX_MEMBERS, RESOURCES, TOKEN_TYPE_ROLE } from '../constants';
import getOrganizationArtifactRegistry from '../graphql/queries/get_organization_artifact_registry.query.graphql';
import getResourceMemberCounts from '../graphql/queries/get_resource_member_counts.query.graphql';
import getResourceMembers from '../graphql/queries/get_resource_members.query.graphql';
import InviteMembersModal, { INVITE_MEMBERS_MODAL_ID } from './invite_members_modal.vue';
import LeaveModal from './leave_modal.vue';
import MemberStats from './member_stats.vue';
import MembersTable from './members_table.vue';
import RemoveMemberModal from './remove_member_modal.vue';
import RoleDetailsDrawer from './role_details_drawer.vue';

// Codes RoleAssignmentsResolver::ERROR_CODES sets on its GraphQL errors.
const ERROR_CODE_DENIED = 'denied';
const ERROR_CODE_UNAVAILABLE = 'unavailable';

const ERROR_MESSAGE = s__(
  'OrganizationAccess|An error occurred loading members. Please refresh the page to try again.',
);
const UNAVAILABLE_MESSAGE = s__(
  'OrganizationAccess|Members could not be loaded because the access service is unavailable. Try again later.',
);
const DENIED_MESSAGE = s__("OrganizationAccess|You don't have permission to view these members.");

const roleToken = (data) => ({ type: TOKEN_TYPE_ROLE, value: { data, operator: OPERATOR_IS } });

const invitedAssignment = ({ id, name, username, avatar_url: avatarUrl }, role, createdAt) => ({
  __typename: 'ArtifactRegistryRoleAssignment',
  resourceId: '',
  role,
  createdAt,
  assignee: {
    __typename: 'UserCore',
    id: convertToGraphQLId(TYPENAME_USER, id),
    name,
    username,
    webPath: '#',
    avatarUrl: avatarUrl || null,
  },
  userPermissions: {
    __typename: 'ArtifactRegistryRoleAssignmentPermissions',
    updateRole: true,
    removeMember: true,
    leave: false,
  },
});

export default {
  name: 'OrganizationAccessResourceApp',
  components: {
    GlButton,
    GlEmptyState,
    GlFilteredSearch,
    InviteMembersModal,
    LeaveModal,
    MemberStats,
    MembersTable,
    PageHeading,
    RemoveMemberModal,
    RoleDetailsDrawer,
  },
  directives: { GlModal: GlModalDirective },
  inject: ['organizationGid', 'canInviteMembers'],
  props: {
    resourceKey: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      registry: null,
      roleAssignments: null,
      counts: null,
      hasError: false,
      hasCountsError: false,
      isLoadingMore: false,
      filterValue: [],
      filters: { search: null, role: null },
      // Local until the Phase 4 wiring (https://gitlab.com/groups/gitlab-org/-/epics/23635)
      // calls the real mutations and refetches.
      invited: [],
      roleChanges: {},
      removedIds: [],
      selectedMemberId: null,
      memberToRemove: null,
      memberLeaving: null,
    };
  },
  apollo: {
    registry: {
      query: getOrganizationArtifactRegistry,
      variables() {
        return { organizationId: this.organizationGid };
      },
      update({ organization }) {
        return organization?.artifactRegistry ?? null;
      },
      error(error) {
        this.showError(error);
      },
    },
    roleAssignments: {
      query: getResourceMembers,
      variables() {
        // A role on Artifact Registry is granted on the registry namespace.
        const { role } = this.filters;
        return { resourceId: this.registry.id, roles: role ? [role] : [], first: MAX_MEMBERS };
      },
      skip() {
        return !this.registry;
      },
      update({ artifactRegistryRoleAssignments }) {
        return artifactRegistryRoleAssignments ?? null;
      },
      error(error) {
        this.showError(error);
      },
    },
    // Mocked until https://gitlab.com/gitlab-org/gitlab/-/issues/632260.
    counts: {
      query: getResourceMemberCounts,
      variables() {
        return { resourceId: this.registry.id };
      },
      skip() {
        return !this.registry;
      },
      update({ artifactRegistryRoleAssignmentCounts }) {
        return artifactRegistryRoleAssignmentCounts ?? null;
      },
      // Counts only feed the stats, so a failure hides the stats but keeps the members table.
      error(error) {
        this.hasCountsError = true;
        createAlert({ message: this.errorMessage(error), error, captureError: true });
      },
    },
  },
  computed: {
    resource() {
      return RESOURCES[this.resourceKey];
    },
    hasNoRegistry() {
      return !this.$apollo.queries.registry.loading && !this.hasError && !this.registry;
    },
    showInviteButton() {
      return (
        this.canInviteMembers &&
        !this.hasError &&
        !this.$apollo.queries.registry.loading &&
        !this.hasNoRegistry
      );
    },
    members() {
      return (this.roleAssignments?.nodes ?? []).filter((node) => node?.assignee);
    },
    hasNextPage() {
      return Boolean(this.roleAssignments?.pageInfo?.hasNextPage);
    },
    invitedIds() {
      return new Set(this.invited.map(({ assignee }) => assignee.id));
    },
    replacedMembers() {
      return this.members.filter(({ assignee }) => this.invitedIds.has(assignee.id));
    },
    // Loaded rows not replaced by an invite.
    loadedMembers() {
      return this.members.filter(({ assignee }) => !this.invitedIds.has(assignee.id));
    },
    removedMembers() {
      return this.loadedMembers.filter(({ assignee }) => this.removedIds.includes(assignee.id));
    },
    keptMembers() {
      return this.loadedMembers.filter(({ assignee }) => !this.removedIds.includes(assignee.id));
    },
    editedMembers() {
      return this.keptMembers.filter(({ assignee }) => assignee.id in this.roleChanges);
    },
    allMembers() {
      return [...this.invited, ...this.keptMembers.map((member) => this.withChangedRole(member))];
    },
    selectedMember() {
      return this.allMembers.find(({ assignee }) => assignee.id === this.selectedMemberId) || null;
    },
    isLoadingMembers() {
      return (
        this.$apollo.queries.registry.loading ||
        (this.$apollo.queries.roleAssignments.loading && !this.isLoadingMore)
      );
    },
    isLoadingStats() {
      return this.$apollo.queries.registry.loading || this.$apollo.queries.counts.loading;
    },
    stats() {
      const {
        adminRole,
        ownerRole,
        adminStatTitle,
        adminFilterLabel,
        ownerStatTitle,
        ownerFilterLabel,
      } = this.resource;
      const added = [
        ...this.invited,
        ...this.editedMembers.map((member) => this.withChangedRole(member)),
      ];
      const removed = [...this.replacedMembers, ...this.editedMembers, ...this.removedMembers];
      const withRole = (list, value) => list.filter(({ role }) => role === value).length;
      const countRole = (value) =>
        (this.counts?.byRole.find(({ role }) => role === value)?.count || 0) +
        withRole(added, value) -
        withRole(removed, value);

      return [
        {
          title: adminStatTitle,
          value: countRole(adminRole),
          filter: roleToken(adminRole),
          filterLabel: adminFilterLabel,
        },
        {
          title: ownerStatTitle,
          value: countRole(ownerRole),
          filter: roleToken(ownerRole),
          filterLabel: ownerFilterLabel,
        },
        {
          title: s__('OrganizationAccess|Total members'),
          value: (this.counts?.total || 0) + added.length - removed.length,
        },
      ];
    },
    availableTokens() {
      return [
        {
          type: TOKEN_TYPE_ROLE,
          title: s__('OrganizationAccess|Role'),
          icon: 'key',
          token: GlFilteredSearchToken,
          operators: OPERATORS_IS,
          unique: true,
          options: this.resource.roles.map(({ value, text }) => ({ value, title: text })),
        },
      ];
    },
    hasActiveFilters() {
      return Object.values(this.filters).some(Boolean);
    },
    filteredMembers() {
      const { search, role } = this.filters;
      const query = search?.toLowerCase().replace(/^@/, '');

      return this.allMembers.filter((member) => {
        if (role && member.role !== role) return false;
        if (!query) return true;

        const { name, username } = member.assignee;
        return name.toLowerCase().includes(query) || username.toLowerCase().includes(query);
      });
    },
  },
  methods: {
    showError(error) {
      this.hasError = true;
      createAlert({ message: this.errorMessage(error), error, captureError: true });
    },
    errorMessage(error) {
      const code = error?.graphQLErrors?.[0]?.extensions?.code;

      if (code === ERROR_CODE_UNAVAILABLE) return UNAVAILABLE_MESSAGE;
      if (code === ERROR_CODE_DENIED) return DENIED_MESSAGE;

      return parseErrorMessage(error, ERROR_MESSAGE);
    },
    async loadMore() {
      this.isLoadingMore = true;

      try {
        await this.$apollo.queries.roleAssignments.fetchMore({
          variables: { after: this.roleAssignments.pageInfo.endCursor },
        });
      } catch (error) {
        createAlert({ message: this.errorMessage(error), error, captureError: true });
      } finally {
        this.isLoadingMore = false;
      }
    },
    withChangedRole(member) {
      const role = this.roleChanges[member.assignee.id];
      return role ? { ...member, role } : member;
    },
    onInput(value) {
      this.filterValue = value;
    },
    onSubmit(terms) {
      // The `submit` payload has free text as plain strings and tokens as
      // `{ type, value: { data } }`, even with `terms-as-tokens`.
      const search = terms
        .filter((term) => typeof term === 'string')
        .map((term) => term.trim())
        .join(' ');

      this.filters = {
        search: search || null,
        role: terms.find((term) => term.type === TOKEN_TYPE_ROLE)?.value.data ?? null,
      };
    },
    onClear() {
      this.filterValue = [];
      this.filters = { search: null, role: null };
    },
    onStatFilter(token) {
      this.filterValue = [token];
      this.onSubmit([token]);
    },
    onTokenDestroy({ type }) {
      if (type === TOKEN_TYPE_ROLE) this.filters = { ...this.filters, role: null };
    },
    onInvite({ users, role }) {
      const createdAt = new Date().toISOString();
      const invited = users.map((user) => invitedAssignment(user, role, createdAt));
      const ids = new Set(invited.map(({ assignee }) => assignee.id));

      this.invited = [...invited, ...this.invited.filter(({ assignee }) => !ids.has(assignee.id))];
      this.removedIds = this.removedIds.filter((id) => !ids.has(id));
      showGlobalToast(
        n__(
          'OrganizationAccess|Member was successfully added.',
          'OrganizationAccess|Members were successfully added.',
          users.length,
        ),
      );
    },
    onUpdateRole({ member, role }) {
      const { id } = member.assignee;

      if (this.invitedIds.has(id)) {
        this.invited = this.invited.map((row) => (row.assignee.id === id ? { ...row, role } : row));
      } else {
        this.roleChanges = { ...this.roleChanges, [id]: role };
      }

      showGlobalToast(s__('OrganizationAccess|Role updated successfully.'));
    },
    removeRow({ assignee: { id } }) {
      this.invited = this.invited.filter(({ assignee }) => assignee.id !== id);
      this.removedIds = [...this.removedIds, id];
      if (this.selectedMemberId === id) this.selectedMemberId = null;
    },
    onRemoveMember({ member }) {
      this.removeRow(member);
      showGlobalToast(s__('OrganizationAccess|Member was successfully removed.'));
    },
    onLeave({ member }) {
      this.removeRow(member);
      showGlobalToast(
        sprintf(s__('OrganizationAccess|You left %{resource}.'), { resource: this.resource.label }),
      );
    },
  },
  inviteMembersModalId: INVITE_MEMBERS_MODAL_ID,
};
</script>

<template>
  <div>
    <page-heading :heading="resource.label">
      <template v-if="showInviteButton" #actions>
        <gl-button v-gl-modal="$options.inviteMembersModalId" variant="confirm">
          {{ s__('OrganizationAccess|Invite members') }}
        </gl-button>
      </template>
    </page-heading>
    <gl-empty-state
      v-if="hasNoRegistry"
      illustration-name="empty-user-md"
      :title="s__('OrganizationAccess|Artifact Registry isn\'t available for this organization.')"
      :description="
        s__('OrganizationAccess|It might not be turned on, or you might not have access.')
      "
      data-testid="no-registry-empty-state"
    />
    <template v-else-if="!hasError">
      <member-stats
        v-if="!hasCountsError"
        :stats="stats"
        :loading="isLoadingStats"
        class="gl-mb-5"
        @filter="onStatFilter"
      />
      <gl-filtered-search
        :value="filterValue"
        :placeholder="s__('OrganizationAccess|Search by name or username')"
        :available-tokens="availableTokens"
        :clear-button-title="__('Clear')"
        :close-button-title="__('Close')"
        terms-as-tokens
        @input="onInput"
        @submit="onSubmit"
        @clear="onClear"
        @token-destroy="onTokenDestroy"
      />
      <members-table
        :resource="resource"
        :members="filteredMembers"
        :loading="isLoadingMembers"
        :has-active-filters="hasActiveFilters"
        class="gl-mt-5"
        @select-member="selectedMemberId = $event.assignee.id"
        @remove-member="memberToRemove = $event"
        @leave="memberLeaving = $event"
      />
      <div v-if="hasNextPage && !isLoadingMembers" class="gl-mt-5 gl-flex gl-justify-center">
        <gl-button :loading="isLoadingMore" data-testid="load-more-members" @click="loadMore">
          {{ __('Load more') }}
        </gl-button>
      </div>
      <invite-members-modal :resource="resource" @invite="onInvite" />
      <role-details-drawer
        :resource="resource"
        :member="selectedMember"
        @close="selectedMemberId = null"
        @update-role="onUpdateRole"
      />
      <remove-member-modal
        :resource="resource"
        :member="memberToRemove"
        @close="memberToRemove = null"
        @remove="onRemoveMember"
      />
      <leave-modal
        :resource="resource"
        :member="memberLeaving"
        @close="memberLeaving = null"
        @leave="onLeave"
      />
    </template>
  </div>
</template>
