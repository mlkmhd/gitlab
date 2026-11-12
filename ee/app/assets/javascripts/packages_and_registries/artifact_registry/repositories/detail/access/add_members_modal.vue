<script>
import {
  GlAlert,
  GlAvatar,
  GlAvatarLabeled,
  GlFormGroup,
  GlModal,
  GlSprintf,
  GlToastMixin,
  GlTokenSelector,
} from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { DEFAULT_DEBOUNCE_AND_THROTTLE_MS } from '~/lib/utils/constants';
import { __, n__, s__, sprintf } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import RoleSelector from '~/members/components/role_selector.vue';
import bulkGrantRepositoryRolesMutation from '../../../graphql/mutations/bulk_grant_repository_roles.mutation.graphql';
import getOrganizationMembersQuery from '../../../graphql/queries/get_organization_members.query.graphql';
import getRepositoryRoleAssignmentsQuery from '../../../graphql/queries/get_repository_role_assignments.query.graphql';
import { ROLE_NAMES } from './constants';
import RoleAccessSummary from './role_access_summary.vue';

const DEFAULT_ROLE = 'ARTIFACT_VIEWER';

const GRANTABLE_ROLES = [
  'ARTIFACT_ADMIN',
  'ARTIFACT_MANAGER',
  'ARTIFACT_CONTRIBUTOR',
  'ARTIFACT_VIEWER',
];

const ROLE_DESCRIPTIONS = {
  ARTIFACT_VIEWER: s__('ArtifactRegistry|Pull and browse artifacts.'),
  ARTIFACT_CONTRIBUTOR: s__('ArtifactRegistry|Publish artifacts (for example, CI jobs).'),
  ARTIFACT_MANAGER: s__('ArtifactRegistry|Manage artifacts and repository configuration.'),
  ARTIFACT_ADMIN: s__('ArtifactRegistry|Manage repository configuration and access.'),
};

const ROLE_ITEMS = GRANTABLE_ROLES.map((role) => ({
  value: role,
  text: ROLE_NAMES[role],
  description: ROLE_DESCRIPTIONS[role],
}));

// `organizationUsers(search:)` only matches partial terms of three characters or more.
const MIN_SEARCH_LENGTH = 3;

const SEARCH_PAGE_SIZE = 20;

export default {
  name: 'ArtifactRegistryAddMembersModal',
  components: {
    GlAlert,
    GlAvatar,
    GlAvatarLabeled,
    GlFormGroup,
    GlModal,
    GlSprintf,
    GlTokenSelector,
    RoleAccessSummary,
    RoleSelector,
  },
  mixins: [GlToastMixin],
  inject: ['organizationGid'],
  model: {
    prop: 'visible',
    event: 'change',
  },
  props: {
    visible: {
      type: Boolean,
      required: true,
    },
    repositoryId: {
      type: String,
      required: true,
    },
    repositoryName: {
      type: String,
      required: true,
    },
    excludedMemberIds: {
      type: Array,
      required: false,
      default: () => [],
    },
    returnFocus: {
      type: HTMLElement,
      required: false,
      default: null,
    },
  },
  emits: ['change'],
  data() {
    return {
      members: [],
      search: '',
      selectedMembers: [],
      role: DEFAULT_ROLE,
      errors: [],
      isSubmitting: false,
      hasSearchFailed: false,
      announcement: '',
      modalId: uniqueId('add-members-modal-'),
      memberInputId: uniqueId('add-members-search-'),
      roleToggleId: uniqueId('add-members-role-'),
    };
  },
  apollo: {
    members: {
      query: getOrganizationMembersQuery,
      debounce: DEFAULT_DEBOUNCE_AND_THROTTLE_MS,
      variables() {
        return {
          organizationId: this.organizationGid,
          search: this.searchTerm,
          first: SEARCH_PAGE_SIZE,
        };
      },
      skip() {
        return !this.isSearchable;
      },
      update: ({ organization }) =>
        (organization?.organizationUsers?.nodes ?? []).map(({ user }) => ({
          id: user.id,
          name: user.name,
          username: user.username,
          avatarUrl: user.avatarUrl,
        })),
      result({ loading, data }) {
        if (loading || !data) return;

        this.hasSearchFailed = false;
        this.announcement = this.$options.i18n.membersFound(this.candidates.length);
      },
      error() {
        this.hasSearchFailed = true;
        this.announcement = this.$options.i18n.searchFailed;
      },
    },
  },
  computed: {
    selectedRole() {
      return ROLE_ITEMS.find(({ value }) => value === this.role);
    },
    searchTerm() {
      return this.search.trim();
    },
    isSearchable() {
      return this.searchTerm.length >= MIN_SEARCH_LENGTH;
    },
    isSearching() {
      return this.$apollo.queries.members.loading;
    },
    candidates() {
      if (!this.isSearchable || this.hasSearchFailed) return [];

      const selectedIds = this.selectedMembers.map(({ id }) => id);

      return this.members.filter(
        ({ id }) => !this.excludedMemberIds.includes(id) && !selectedIds.includes(id),
      );
    },
    noResultsText() {
      return this.hasSearchFailed ? this.$options.i18n.searchFailed : this.$options.i18n.noMatches;
    },
    placeholder() {
      return this.selectedMembers.length ? '' : this.$options.i18n.searchPlaceholder;
    },
    primaryAction() {
      return {
        text: this.$options.i18n.add,
        attributes: {
          variant: 'confirm',
          disabled: this.selectedMembers.length === 0,
          loading: this.isSubmitting,
        },
      };
    },
  },
  watch: {
    isSearchable(searchable) {
      if (!searchable) this.members = [];
    },
  },
  methods: {
    onPrimary(event) {
      event.preventDefault();
      this.submit();
    },
    async submit() {
      this.isSubmitting = true;
      this.errors = [];

      try {
        const errors = await this.grantRoles();

        if (errors.length) {
          this.errors = errors.flatMap((error) => error.split('\n'));
          return;
        }

        this.$toast.show(this.successMessage());
        this.$emit('change', false);
      } catch (error) {
        Sentry.captureException(error);
        this.errors = [this.$options.i18n.genericError];
      } finally {
        this.isSubmitting = false;
      }
    },
    async grantRoles() {
      const assignments = this.selectedMembers.map(({ id }) => ({
        assigneeId: id,
        resourceId: this.repositoryId,
        role: this.role,
      }));

      const { data } = await this.$apollo.mutate({
        mutation: bulkGrantRepositoryRolesMutation,
        variables: { input: { assignments } },
        // A refetch keeps the Direct members rows until the new page arrives, unlike an eviction.
        refetchQueries: ({ data: result }) =>
          result.bulkGrantRoles.errors.length ? [] : [getRepositoryRoleAssignmentsQuery],
      });

      return data.bulkGrantRoles.errors;
    },
    successMessage() {
      const count = this.selectedMembers.length;

      return sprintf(
        this.$options.i18n.membersAdded(count),
        { count, role: ROLE_NAMES[this.role] },
        false,
      );
    },
    onMemberSearchEscape(event) {
      if (event.target.getAttribute('aria-expanded') !== 'true') this.$refs.modal.hide();
    },
    onHide(event) {
      if (this.isSubmitting) event.preventDefault();
    },
    onHidden() {
      this.selectedMembers = [];
      this.role = DEFAULT_ROLE;
      this.errors = [];
      this.search = '';
      this.announcement = '';
      this.hasSearchFailed = false;
    },
  },
  cancelAction: { text: __('Cancel') },
  roles: { formatted: ROLE_ITEMS, flatten: ROLE_ITEMS },
  avatarSize: 32,
  tokenAvatarSize: 16,
  i18n: {
    title: s__('ArtifactRegistry|Add members'),
    add: s__('ArtifactRegistry|Add'),
    intro: s__("ArtifactRegistry|You're adding members to the %{name} repository."),
    membersLabel: s__('ArtifactRegistry|Organization members'),
    membersHelp: s__('ArtifactRegistry|Select from GitLab usernames.'),
    searchPlaceholder: s__('ArtifactRegistry|Search by name or username'),
    noMatches: s__('ArtifactRegistry|No matches found.'),
    searchFailed: s__('ArtifactRegistry|Members could not be loaded.'),
    roleLabel: s__('ArtifactRegistry|Role'),
    roleHeader: s__('ArtifactRegistry|Select a role'),
    genericError: __('Something went wrong. Please try again.'),
    membersFound: (count) =>
      n__('ArtifactRegistry|%d member found.', 'ArtifactRegistry|%d members found.', count),
    membersAdded: (count) =>
      n__(
        'ArtifactRegistry|%{count} member added as %{role}. Changes might not take effect right away.',
        'ArtifactRegistry|%{count} members added as %{role}. Changes might not take effect right away.',
        count,
      ),
  },
};
</script>

<template>
  <gl-modal
    ref="modal"
    :return-focus="returnFocus"
    :modal-id="modalId"
    :visible="visible"
    :title="$options.i18n.title"
    :action-primary="primaryAction"
    :action-cancel="$options.cancelAction"
    size="sm"
    no-close-on-backdrop
    data-testid="add-members-modal"
    @primary="onPrimary"
    @change="$emit('change', $event)"
    @hide="onHide"
    @hidden="onHidden"
  >
    <p class="gl-wrap-anywhere" data-testid="add-members-intro">
      <gl-sprintf :message="$options.i18n.intro">
        <template #name>
          <strong>{{ repositoryName }}</strong>
        </template>
      </gl-sprintf>
    </p>

    <gl-alert
      v-if="errors.length"
      variant="danger"
      :dismissible="false"
      class="gl-mb-5"
      data-testid="add-members-errors"
    >
      <ul class="gl-mb-0 gl-pl-5">
        <li v-for="(line, index) in errors" :key="index">{{ line }}</li>
      </ul>
    </gl-alert>

    <gl-form-group
      :label="$options.i18n.membersLabel"
      :label-for="memberInputId"
      :description="$options.i18n.membersHelp"
    >
      <!-- GlTokenSelector stops Esc from reaching the modal, so close it here unless its dropdown is open. -->
      <div @keydown.esc.capture="onMemberSearchEscape">
        <gl-token-selector
          :selected-tokens="selectedMembers"
          :dropdown-items="candidates"
          :loading="isSearching"
          :hide-dropdown-with-no-items="!isSearchable"
          :placeholder="placeholder"
          :text-input-attrs="{ id: memberInputId, 'data-testid': 'member-search' }"
          menu-class="gl-w-auto gl-min-w-full"
          data-testid="member-picker"
          @text-input="search = $event"
          @input="selectedMembers = $event"
        >
          <template #token-content="{ token }">
            <gl-avatar
              v-if="token.avatarUrl"
              :src="token.avatarUrl"
              :size="$options.tokenAvatarSize"
              :alt="''"
            />
            {{ token.name }}
          </template>

          <template #dropdown-item-content="{ dropdownItem }">
            <gl-avatar-labeled
              :src="dropdownItem.avatarUrl"
              :entity-name="dropdownItem.name"
              :label="dropdownItem.name"
              :sub-label="`@${dropdownItem.username}`"
              :size="$options.avatarSize"
            />
          </template>

          <template #no-results-content>
            {{ noResultsText }}
          </template>
        </gl-token-selector>
      </div>
    </gl-form-group>

    <gl-form-group :label="$options.i18n.roleLabel" :label-for="roleToggleId">
      <role-selector
        :roles="$options.roles"
        :value="selectedRole"
        :toggle-id="roleToggleId"
        :header-text="$options.i18n.roleHeader"
        @input="role = $event.value"
      />
    </gl-form-group>

    <role-access-summary :role="role" />

    <span
      class="gl-sr-only"
      aria-live="polite"
      aria-atomic="true"
      data-testid="member-search-announcement"
      >{{ announcement }}</span
    >
  </gl-modal>
</template>
