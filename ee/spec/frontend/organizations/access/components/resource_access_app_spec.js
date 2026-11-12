import { GlButton, GlEmptyState, GlFilteredSearch } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import { useFakeDate } from 'helpers/fake_date';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import InviteMembersModal from 'ee/organizations/access/components/invite_members_modal.vue';
import LeaveModal from 'ee/organizations/access/components/leave_modal.vue';
import OrganizationAccessResourceApp from 'ee/organizations/access/components/resource_access_app.vue';
import MemberStats from 'ee/organizations/access/components/member_stats.vue';
import MembersTable from 'ee/organizations/access/components/members_table.vue';
import RemoveMemberModal from 'ee/organizations/access/components/remove_member_modal.vue';
import RoleDetailsDrawer from 'ee/organizations/access/components/role_details_drawer.vue';
import { cacheConfig } from 'ee/organizations/access/graphql/cache_config';
import { createMockResolvers } from 'ee/organizations/access/graphql/mock_resolvers';
import getOrganizationArtifactRegistry from 'ee/organizations/access/graphql/queries/get_organization_artifact_registry.query.graphql';
import getResourceMembers from 'ee/organizations/access/graphql/queries/get_resource_members.query.graphql';
import { createAlert } from '~/alert';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import showGlobalToast from '~/vue_shared/plugins/global_toast';

jest.mock('~/alert');
jest.mock('~/vue_shared/plugins/global_toast');

Vue.use(VueApollo);

const ORGANIZATION_GID = 'gid://gitlab/Organizations::Organization/1';
const NAMESPACE_ID = '0b5b2a8e-6f0a-4c1e-9d2a-1f7d3c4b5a69';

const assignment = ([id, name, username], role) => ({
  __typename: 'ArtifactRegistryRoleAssignment',
  resourceId: NAMESPACE_ID,
  role,
  createdAt: '2026-09-01T00:00:00Z',
  assignee: {
    __typename: 'UserCore',
    id: `gid://gitlab/User/${id}`,
    name,
    username,
    webPath: '#',
    avatarUrl: null,
  },
  userPermissions: {
    __typename: 'ArtifactRegistryRoleAssignmentPermissions',
    updateRole: true,
    removeMember: true,
    leave: false,
  },
});

const ASSIGNMENTS = [
  assignment([1, 'Alex Garcia', 'agarcia'], 'ARTIFACT_ADMIN'),
  assignment([2, 'Priya Shah', 'pshah'], 'ARTIFACT_MANAGER'),
  assignment([3, 'Morgan Lee', 'mlee'], 'ARTIFACT_ADMIN'),
  assignment([4, 'Sam Rivera', 'srivera'], 'ARTIFACT_CONTRIBUTOR'),
  assignment([5, 'Jordan Kim', 'jkim'], 'ARTIFACT_VIEWER'),
];
const ALL = ['agarcia', 'pshah', 'mlee', 'srivera', 'jkim'];

const registryResponse = (
  artifactRegistry = { __typename: 'ArtifactRegistry', id: NAMESPACE_ID },
) => ({
  data: {
    organization: {
      __typename: 'Organization',
      id: ORGANIZATION_GID,
      artifactRegistry,
    },
  },
});

const membersResponse = (nodes, { hasNextPage = false, endCursor = null } = {}) => ({
  data: {
    artifactRegistryRoleAssignments: {
      __typename: 'ArtifactRegistryRoleAssignmentConnection',
      nodes,
      pageInfo: { __typename: 'PageInfo', hasNextPage, endCursor },
    },
  },
});

// Filters by `roles` the way the API does.
const membersHandlerFor = (assignments) =>
  jest.fn(({ roles = [] }) =>
    Promise.resolve(
      membersResponse(assignments.filter(({ role }) => !roles.length || roles.includes(role))),
    ),
  );

const graphQLError = (code) => ({
  errors: [{ message: 'Lookup failed', extensions: { code } }],
});

describe('OrganizationAccessResourceApp', () => {
  let wrapper;

  let registryHandler;
  let membersHandler;

  const createComponent = ({
    registry = jest.fn().mockResolvedValue(registryResponse()),
    members = membersHandlerFor(ASSIGNMENTS),
    resolvers = createMockResolvers(ASSIGNMENTS),
    canInviteMembers = true,
  } = {}) => {
    registryHandler = registry;
    membersHandler = members;
    wrapper = shallowMountExtended(OrganizationAccessResourceApp, {
      apolloProvider: createMockApollo(
        [
          [getOrganizationArtifactRegistry, registryHandler],
          [getResourceMembers, membersHandler],
        ],
        resolvers,
        { typePolicies: cacheConfig.typePolicies },
      ),
      provide: { organizationGid: ORGANIZATION_GID, canInviteMembers },
      propsData: { resourceKey: 'artifact-registry' },
      directives: { GlModal: createMockDirective('gl-modal') },
      stubs: { PageHeading },
    });
  };

  const findMemberStats = () => wrapper.findComponent(MemberStats);
  const findFilteredSearch = () => wrapper.findComponent(GlFilteredSearch);
  const findMembersTable = () => wrapper.findComponent(MembersTable);
  const findInviteButton = () => wrapper.findComponent(GlButton);
  const findLoadMore = () => wrapper.findComponentByTestId('load-more-members');
  const findNoRegistry = () => wrapper.findComponent(GlEmptyState);
  const findInviteModal = () => wrapper.findComponent(InviteMembersModal);
  const findDrawer = () => wrapper.findComponent(RoleDetailsDrawer);
  const findRemoveModal = () => wrapper.findComponent(RemoveMemberModal);
  const findLeaveModal = () => wrapper.findComponent(LeaveModal);
  const findRow = (username) =>
    findMembersTable()
      .props('members')
      .find(({ assignee }) => assignee.username === username);
  const findStatValues = () =>
    findMemberStats()
      .props('stats')
      .map(({ value }) => value);
  const findMembers = () =>
    findMembersTable()
      .props('members')
      .map(({ assignee, role, createdAt }) => [assignee.username, role, createdAt]);
  const findUsernames = () =>
    findMembersTable()
      .props('members')
      .map(({ assignee }) => assignee.username);
  const findToken = (type) =>
    findFilteredSearch()
      .props('availableTokens')
      .find((token) => token.type === type);

  const submit = async (terms) => {
    findFilteredSearch().vm.$emit('submit', terms);
    await nextTick();
  };
  const roleToken = (data) => ({ type: 'role', value: { data, operator: '=' } });

  it('passes the loading state to the table while members load', () => {
    createComponent();

    expect(findMembersTable().props('loading')).toBe(true);
    expect(findMemberStats().props('loading')).toBe(true);
  });

  it('keeps the stats loading when members load before the counts', async () => {
    const resolvers = createMockResolvers(ASSIGNMENTS);
    resolvers.Query.artifactRegistryRoleAssignmentCounts = () => new Promise(() => {});
    createComponent({ resolvers });
    await waitForPromises();

    expect(findMembersTable().props('loading')).toBe(false);
    expect(findMembersTable().props('members')).toHaveLength(ASSIGNMENTS.length);
    expect(findMemberStats().props('loading')).toBe(true);
  });

  it('does not render the invite button while the registry loads', () => {
    createComponent();

    expect(findInviteButton().exists()).toBe(false);
  });

  it('reads the registry of the organization', async () => {
    createComponent();
    await waitForPromises();

    expect(registryHandler).toHaveBeenCalledWith({ organizationId: ORGANIZATION_GID });
  });

  it('reads the first page of members on the registry namespace', async () => {
    createComponent();
    await waitForPromises();

    expect(membersHandler).toHaveBeenCalledTimes(1);
    expect(membersHandler).toHaveBeenCalledWith({
      resourceId: NAMESPACE_ID,
      roles: [],
      first: 100,
    });
  });

  it('passes no members to the table when the assignments connection is null', async () => {
    createComponent({
      members: jest.fn().mockResolvedValue({ data: { artifactRegistryRoleAssignments: null } }),
    });
    await waitForPromises();

    expect(findMembersTable().props('members')).toEqual([]);
    expect(findMemberStats().props('stats')[2].value).toBe(5);
  });

  describe('when the organization has no registry', () => {
    beforeEach(async () => {
      createComponent({ registry: jest.fn().mockResolvedValue(registryResponse(null)) });
      await waitForPromises();
    });

    it('shows an empty state', () => {
      expect(findNoRegistry().props('title')).toBe(
        "Artifact Registry isn't available for this organization.",
      );
    });

    it('does not read members', () => {
      expect(membersHandler).not.toHaveBeenCalled();
    });

    it('does not render the invite button, stats, search, or table', () => {
      expect(findInviteButton().exists()).toBe(false);
      expect(findMemberStats().exists()).toBe(false);
      expect(findFilteredSearch().exists()).toBe(false);
      expect(findMembersTable().exists()).toBe(false);
    });
  });

  describe('when an assignment has a null role', () => {
    beforeEach(async () => {
      createComponent({
        members: membersHandlerFor([
          { ...assignment([6, 'Owner User', 'owner'], null) },
          ...ASSIGNMENTS,
        ]),
      });
      await waitForPromises();
    });

    it('passes the row to the table', () => {
      expect(findRow('owner').role).toBeNull();
    });
  });

  describe('when an assignment has a null assignee', () => {
    beforeEach(async () => {
      createComponent({
        members: membersHandlerFor([
          ...ASSIGNMENTS,
          { ...assignment([6, 'Gone User', 'gone'], 'ARTIFACT_VIEWER'), assignee: null },
        ]),
      });
      await waitForPromises();
    });

    it('leaves the assignment out of the table', () => {
      expect(findUsernames()).toEqual(ALL);
    });

    it('still filters by name or username', async () => {
      await submit(['alex']);

      expect(findUsernames()).toEqual(['agarcia']);
    });
  });

  describe('when members have loaded', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders the resource label as the heading without a description', () => {
      expect(wrapper.findByTestId('page-heading').text()).toBe('Artifact Registry');
      expect(wrapper.findByTestId('page-heading-description').exists()).toBe(false);
    });

    it('passes the admin, owner, and total counts to the stats', () => {
      expect(findMemberStats().props('stats')).toEqual([
        {
          title: 'Artifact Admins',
          value: 2,
          filter: roleToken('ARTIFACT_ADMIN'),
          filterLabel: 'Filter list for Artifact Admins',
        },
        {
          title: 'Artifact Managers',
          value: 1,
          filter: roleToken('ARTIFACT_MANAGER'),
          filterLabel: 'Filter list for Artifact Managers',
        },
        { title: 'Total members', value: 5 },
      ]);
    });

    it('renders the search with a placeholder', () => {
      expect(findFilteredSearch().props()).toMatchObject({
        placeholder: 'Search by name or username',
        termsAsTokens: true,
      });
    });

    it('offers only a unique Role token with the resource roles', () => {
      expect(findFilteredSearch().props('availableTokens')).toHaveLength(1);
      expect(findToken('role')).toMatchObject({
        title: 'Role',
        unique: true,
        operators: [{ value: '=', description: 'is' }],
        options: [
          { value: 'ARTIFACT_ADMIN', title: 'Artifact Admin' },
          { value: 'ARTIFACT_MANAGER', title: 'Artifact Manager' },
          { value: 'ARTIFACT_CONTRIBUTOR', title: 'Artifact Contributor' },
          { value: 'ARTIFACT_VIEWER', title: 'Artifact Viewer' },
        ],
      });
    });

    it('passes all members, the resource, and no loading state to the table', () => {
      expect(findMembersTable().props('resource').label).toBe('Artifact Registry');
      expect(findMembersTable().props('loading')).toBe(false);
      expect(findMemberStats().props('loading')).toBe(false);
      expect(findUsernames()).toEqual(ALL);
    });

    describe('hasActiveFilters', () => {
      it('is false with no filters', () => {
        expect(findMembersTable().props('hasActiveFilters')).toBe(false);
      });

      it.each`
        description       | terms
        ${'search text'}  | ${['nobody']}
        ${'a role token'} | ${[roleToken('ARTIFACT_VIEWER')]}
      `('is true with $description', async ({ terms }) => {
        await submit(terms);

        expect(findMembersTable().props('hasActiveFilters')).toBe(true);
      });

      it('is false after the search is cleared', async () => {
        await submit(['nobody']);
        findFilteredSearch().vm.$emit('clear');
        await nextTick();

        expect(findMembersTable().props('hasActiveFilters')).toBe(false);
      });
    });

    describe('search', () => {
      it.each`
        term          | expected
        ${'priya'}    | ${['pshah']}
        ${'SRIVERA'}  | ${['srivera']}
        ${'  lee '}   | ${['mlee']}
        ${'@agarcia'} | ${['agarcia']}
        ${'nobody'}   | ${[]}
      `('filters by name or username for "$term"', async ({ term, expected }) => {
        await submit([term]);

        expect(findUsernames()).toEqual(expected);
      });

      it('filters by role through the API', async () => {
        await submit([roleToken('ARTIFACT_ADMIN')]);
        await waitForPromises();

        expect(membersHandler).toHaveBeenLastCalledWith({
          resourceId: NAMESPACE_ID,
          roles: ['ARTIFACT_ADMIN'],
          first: 100,
        });
        expect(findUsernames()).toEqual(['agarcia', 'mlee']);
      });

      it('combines text and role filters', async () => {
        await submit(['alex', roleToken('ARTIFACT_ADMIN')]);
        await waitForPromises();

        expect(findUsernames()).toEqual(['agarcia']);
      });

      it('resets the list when cleared', async () => {
        findMemberStats().vm.$emit('filter', roleToken('ARTIFACT_ADMIN'));
        await waitForPromises();
        findFilteredSearch().vm.$emit('clear');
        await waitForPromises();

        expect(findUsernames()).toEqual(ALL);
        expect(findFilteredSearch().props('value')).toEqual([]);
      });
    });

    describe('when the role token is removed', () => {
      it('clears the role filter', async () => {
        findMemberStats().vm.$emit('filter', roleToken('ARTIFACT_ADMIN'));
        await waitForPromises();
        findFilteredSearch().vm.$emit('token-destroy', roleToken('ARTIFACT_ADMIN'));
        await waitForPromises();

        expect(findUsernames()).toEqual(ALL);
        expect(findMembersTable().props('hasActiveFilters')).toBe(false);
      });
    });

    describe('when a stat card filters the list', () => {
      it.each`
        title                  | token                            | expected
        ${'Artifact Admins'}   | ${roleToken('ARTIFACT_ADMIN')}   | ${['agarcia', 'mlee']}
        ${'Artifact Managers'} | ${roleToken('ARTIFACT_MANAGER')} | ${['pshah']}
      `('sets the token and filters for $title', async ({ token, expected }) => {
        findMemberStats().vm.$emit('filter', token);
        await waitForPromises();

        expect(findFilteredSearch().props('value')).toEqual([token]);
        expect(findUsernames()).toEqual(expected);
      });
    });
  });

  describe('inviting members', () => {
    useFakeDate(2026, 9, 23, 12);

    const NOW = '2026-10-23T12:00:00.000Z';
    const invite = async (users, role) => {
      findInviteModal().vm.$emit('invite', { users, role });
      await waitForPromises();
    };

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('opens the invite modal from the Invite members button', () => {
      expect(findInviteButton().text()).toBe('Invite members');
      expect(findInviteButton().props('variant')).toBe('confirm');
      expect(getBinding(findInviteButton().element, 'gl-modal').value).toBe(
        'organization-access-invite-members-modal',
      );
      expect(findInviteModal().props('resource').label).toBe('Artifact Registry');
    });

    it('hides the Invite members button when the user cannot invite members', async () => {
      createComponent({ canInviteMembers: false });
      await waitForPromises();

      expect(findInviteButton().exists()).toBe(false);
    });

    describe('when new users are invited', () => {
      beforeEach(async () => {
        await invite(
          [
            { id: 7, name: 'Casey Wu', username: 'cwu', avatar_url: '/avatar.png' },
            { id: 8, name: 'Drew Park', username: 'dpark', avatar_url: null },
          ],
          'ARTIFACT_ADMIN',
        );
      });

      it('adds them to the top of the table with the chosen role', () => {
        expect(findMembers()).toEqual([
          ['cwu', 'ARTIFACT_ADMIN', NOW],
          ['dpark', 'ARTIFACT_ADMIN', NOW],
          ['agarcia', 'ARTIFACT_ADMIN', '2026-09-01T00:00:00Z'],
          ['pshah', 'ARTIFACT_MANAGER', '2026-09-01T00:00:00Z'],
          ['mlee', 'ARTIFACT_ADMIN', '2026-09-01T00:00:00Z'],
          ['srivera', 'ARTIFACT_CONTRIBUTOR', '2026-09-01T00:00:00Z'],
          ['jkim', 'ARTIFACT_VIEWER', '2026-09-01T00:00:00Z'],
        ]);
        expect(findMembersTable().props('members')[0].assignee).toEqual({
          __typename: 'UserCore',
          id: 'gid://gitlab/User/7',
          name: 'Casey Wu',
          username: 'cwu',
          webPath: '#',
          avatarUrl: '/avatar.png',
        });
      });

      it('lets the inviter edit or remove the invited rows', () => {
        expect(findMembersTable().props('members')[0].userPermissions).toMatchObject({
          updateRole: true,
          removeMember: true,
          leave: false,
        });
      });

      it('updates the stats', () => {
        expect(
          findMemberStats()
            .props('stats')
            .map(({ value }) => value),
        ).toEqual([4, 1, 7]);
      });

      it('shows a toast', () => {
        expect(showGlobalToast).toHaveBeenCalledWith('Members were successfully added.');
      });
    });

    describe('when one user is invited', () => {
      it('shows a singular toast', async () => {
        await invite([{ id: 7, name: 'Casey Wu', username: 'cwu' }], 'ARTIFACT_VIEWER');

        expect(showGlobalToast).toHaveBeenCalledWith('Member was successfully added.');
      });
    });

    describe('when an invited user already has a role', () => {
      beforeEach(async () => {
        await invite([{ id: 5, name: 'Jordan Kim', username: 'jkim' }], 'ARTIFACT_MANAGER');
      });

      it('replaces their row', () => {
        expect(findMembers()).toEqual([
          ['jkim', 'ARTIFACT_MANAGER', NOW],
          ['agarcia', 'ARTIFACT_ADMIN', '2026-09-01T00:00:00Z'],
          ['pshah', 'ARTIFACT_MANAGER', '2026-09-01T00:00:00Z'],
          ['mlee', 'ARTIFACT_ADMIN', '2026-09-01T00:00:00Z'],
          ['srivera', 'ARTIFACT_CONTRIBUTOR', '2026-09-01T00:00:00Z'],
        ]);
        expect(
          findMemberStats()
            .props('stats')
            .map(({ value }) => value),
        ).toEqual([2, 2, 5]);
      });
    });

    describe('when an invited user moves out of a counted role', () => {
      beforeEach(async () => {
        await invite([{ id: 1, name: 'Alex Garcia', username: 'agarcia' }], 'ARTIFACT_VIEWER');
      });

      it('lowers the count of their old role', () => {
        expect(
          findMemberStats()
            .props('stats')
            .map(({ value }) => value),
        ).toEqual([1, 1, 5]);
      });
    });

    describe('when an invited user is invited again', () => {
      beforeEach(async () => {
        await invite([{ id: 5, name: 'Jordan Kim', username: 'jkim' }], 'ARTIFACT_MANAGER');
        await invite([{ id: 5, name: 'Jordan Kim', username: 'jkim' }], 'ARTIFACT_ADMIN');
      });

      it('keeps one row with the latest role', () => {
        expect(findMembers().filter(([username]) => username === 'jkim')).toEqual([
          ['jkim', 'ARTIFACT_ADMIN', NOW],
        ]);
        expect(
          findMemberStats()
            .props('stats')
            .map(({ value }) => value),
        ).toEqual([3, 1, 5]);
      });
    });
  });

  describe('selecting a role after an invite', () => {
    beforeEach(async () => {
      wrapper = mountExtended(OrganizationAccessResourceApp, {
        apolloProvider: createMockApollo(
          [
            [getOrganizationArtifactRegistry, jest.fn().mockResolvedValue(registryResponse())],
            [getResourceMembers, membersHandlerFor(ASSIGNMENTS)],
          ],
          createMockResolvers(ASSIGNMENTS),
          { typePolicies: cacheConfig.typePolicies },
        ),
        provide: {
          organizationGid: ORGANIZATION_GID,
          canInviteMembers: true,
          searchUrl: '/users.json',
        },
        propsData: { resourceKey: 'artifact-registry' },
        directives: { GlModal: createMockDirective('gl-modal'), GlTooltip: true },
        stubs: {
          InviteMembersModal: true,
          RoleDetailsDrawer: true,
          RemoveMemberModal: true,
          LeaveModal: true,
        },
      });
      await waitForPromises();
      findInviteModal().vm.$emit('invite', {
        users: [{ id: 7, name: 'Casey Wu', username: 'cwu' }],
        role: 'ARTIFACT_VIEWER',
      });
      await waitForPromises();
    });

    it.each`
      index | username
      ${0}  | ${'cwu'}
      ${1}  | ${'agarcia'}
      ${2}  | ${'pshah'}
    `('opens the drawer for the clicked row ($username)', async ({ index, username }) => {
      await wrapper.findAllByTestId('member-role-button').at(index).trigger('click');

      expect(findDrawer().props('member').assignee.username).toBe(username);
    });
  });

  describe('editing a role', () => {
    const selectMember = async (username) => {
      const row = findMembersTable()
        .props('members')
        .find(({ assignee }) => assignee.username === username);
      findMembersTable().vm.$emit('select-member', row);
      await nextTick();
    };
    const updateRole = async (role) => {
      findDrawer().vm.$emit('update-role', { member: findDrawer().props('member'), role });
      await nextTick();
    };

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders the drawer closed, with the resource', () => {
      expect(findDrawer().props()).toMatchObject({ member: null });
      expect(findDrawer().props('resource').label).toBe('Artifact Registry');
    });

    describe('when a role is clicked', () => {
      beforeEach(async () => {
        await selectMember('jkim');
      });

      it('opens the drawer for that member', () => {
        expect(findDrawer().props('member').assignee.username).toBe('jkim');
      });

      it('clears the selection when the drawer closes', async () => {
        findDrawer().vm.$emit('close');
        await nextTick();

        expect(findDrawer().props('member')).toBeNull();
      });

      describe('when the role is updated', () => {
        beforeEach(async () => {
          await updateRole('ARTIFACT_ADMIN');
        });

        it('changes the role in place', () => {
          expect(findMembers()).toEqual([
            ['agarcia', 'ARTIFACT_ADMIN', '2026-09-01T00:00:00Z'],
            ['pshah', 'ARTIFACT_MANAGER', '2026-09-01T00:00:00Z'],
            ['mlee', 'ARTIFACT_ADMIN', '2026-09-01T00:00:00Z'],
            ['srivera', 'ARTIFACT_CONTRIBUTOR', '2026-09-01T00:00:00Z'],
            ['jkim', 'ARTIFACT_ADMIN', '2026-09-01T00:00:00Z'],
          ]);
        });

        it('updates the stats', () => {
          expect(findStatValues()).toEqual([3, 1, 5]);
        });

        it('keeps the drawer open with the updated member', () => {
          expect(findDrawer().props('member').role).toBe('ARTIFACT_ADMIN');
        });

        it('shows a toast', () => {
          expect(showGlobalToast).toHaveBeenCalledWith('Role updated successfully.');
        });

        it('filters by the new role', async () => {
          await submit([roleToken('ARTIFACT_VIEWER')]);
          await waitForPromises();

          expect(findUsernames()).toEqual([]);
        });
      });
    });

    describe('when an invited member role is updated', () => {
      beforeEach(async () => {
        findInviteModal().vm.$emit('invite', {
          users: [{ id: 7, name: 'Casey Wu', username: 'cwu' }],
          role: 'ARTIFACT_VIEWER',
        });
        await waitForPromises();
        await selectMember('cwu');
        await updateRole('ARTIFACT_MANAGER');
      });

      it('changes the invited row in place', () => {
        expect(findMembers()[0].slice(0, 2)).toEqual(['cwu', 'ARTIFACT_MANAGER']);
        expect(findStatValues()).toEqual([2, 2, 6]);
      });
    });

    describe('when an edited member is invited again', () => {
      beforeEach(async () => {
        await selectMember('jkim');
        await updateRole('ARTIFACT_ADMIN');
        findInviteModal().vm.$emit('invite', {
          users: [{ id: 5, name: 'Jordan Kim', username: 'jkim' }],
          role: 'ARTIFACT_CONTRIBUTOR',
        });
        await waitForPromises();
      });

      it('keeps one row with the invited role', () => {
        expect(
          findMembers()
            .filter(([username]) => username === 'jkim')
            .map(([, role]) => role),
        ).toEqual(['ARTIFACT_CONTRIBUTOR']);
        expect(findStatValues()).toEqual([2, 1, 5]);
      });
    });
  });

  describe.each`
    action      | event              | findModal                  | confirmEvent | toast
    ${'remove'} | ${'remove-member'} | ${() => findRemoveModal()} | ${'remove'}  | ${'Member was successfully removed.'}
    ${'leave'}  | ${'leave'}         | ${() => findLeaveModal()}  | ${'leave'}   | ${'You left Artifact Registry.'}
  `('when a member is chosen to $action', ({ event, findModal, confirmEvent, toast }) => {
    const choose = async (username) => {
      findMembersTable().vm.$emit(event, findRow(username));
      await nextTick();
    };
    const confirm = async () => {
      findModal().vm.$emit(confirmEvent, { member: findModal().props('member') });
      await nextTick();
    };

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders the modal closed, with the resource', () => {
      expect(findModal().props('member')).toBeNull();
      expect(findModal().props('resource').label).toBe('Artifact Registry');
    });

    describe('when chosen', () => {
      beforeEach(async () => {
        await choose('jkim');
      });

      it('opens the modal for that member', () => {
        expect(findModal().props('member').assignee.username).toBe('jkim');
      });

      it('clears the member when the modal closes', async () => {
        findModal().vm.$emit('close');
        await nextTick();

        expect(findModal().props('member')).toBeNull();
      });

      describe('when confirmed', () => {
        beforeEach(async () => {
          await confirm();
        });

        it('removes the row', () => {
          expect(findUsernames()).toEqual(['agarcia', 'pshah', 'mlee', 'srivera']);
        });

        it('updates the stats', () => {
          expect(findStatValues()).toEqual([2, 1, 4]);
        });

        it('shows a toast', () => {
          expect(showGlobalToast).toHaveBeenCalledWith(toast);
        });
      });
    });

    describe('when the drawer is open for the member', () => {
      beforeEach(async () => {
        findMembersTable().vm.$emit('select-member', findRow('agarcia'));
        await choose('agarcia');
        await confirm();
      });

      it('closes the drawer', () => {
        expect(findDrawer().props('member')).toBeNull();
      });
    });

    describe('when the drawer is open for another member', () => {
      beforeEach(async () => {
        findMembersTable().vm.$emit('select-member', findRow('pshah'));
        await choose('agarcia');
        await confirm();
      });

      it('keeps the drawer open', () => {
        expect(findDrawer().props('member').assignee.username).toBe('pshah');
      });
    });
  });

  describe('combining invites, edits, and removals', () => {
    const removeMember = async (username) => {
      findRemoveModal().vm.$emit('remove', { member: findRow(username) });
      await nextTick();
    };
    const invite = async (users, role) => {
      findInviteModal().vm.$emit('invite', { users, role });
      await waitForPromises();
    };

    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('removes an edited member', async () => {
      findDrawer().vm.$emit('update-role', { member: findRow('jkim'), role: 'ARTIFACT_ADMIN' });
      await nextTick();
      await removeMember('jkim');

      expect(findUsernames()).not.toContain('jkim');
      expect(findStatValues()).toEqual([2, 1, 4]);
    });

    it('removes a re-invited member without bringing back their old row', async () => {
      await invite([{ id: 5, name: 'Jordan Kim', username: 'jkim' }], 'ARTIFACT_ADMIN');
      await removeMember('jkim');

      expect(findUsernames()).toEqual(['agarcia', 'pshah', 'mlee', 'srivera']);
      expect(findStatValues()).toEqual([2, 1, 4]);
    });

    it('removes a new invitee', async () => {
      await invite([{ id: 7, name: 'Casey Wu', username: 'cwu' }], 'ARTIFACT_ADMIN');
      await removeMember('cwu');

      expect(findUsernames()).toEqual(ALL);
      expect(findStatValues()).toEqual([2, 1, 5]);
    });

    it('lets a removed member be invited again', async () => {
      await removeMember('jkim');
      await invite([{ id: 5, name: 'Jordan Kim', username: 'jkim' }], 'ARTIFACT_MANAGER');

      expect(findUsernames()).toEqual(['jkim', 'agarcia', 'pshah', 'mlee', 'srivera']);
      expect(findStatValues()).toEqual([2, 2, 5]);
    });
  });

  describe('pagination', () => {
    // An admin, so a stale append would survive the admin role filter.
    const SECOND_PAGE = [assignment([6, 'Casey Wu', 'cwu'], 'ARTIFACT_ADMIN')];

    const pagedHandler = (secondPage = Promise.resolve(membersResponse(SECOND_PAGE))) =>
      jest.fn(({ after, roles = [] }) =>
        after
          ? secondPage
          : Promise.resolve(
              membersResponse(
                ASSIGNMENTS.filter(({ role }) => !roles.length || roles.includes(role)),
                { hasNextPage: true, endCursor: 'cursor-1' },
              ),
            ),
      );

    it('does not render Load more when there is no next page', async () => {
      createComponent();
      await waitForPromises();

      expect(findLoadMore().exists()).toBe(false);
    });

    describe('when there is a next page', () => {
      beforeEach(async () => {
        createComponent({ members: pagedHandler() });
        await waitForPromises();
      });

      it('renders Load more', () => {
        expect(findLoadMore().text()).toBe('Load more');
      });

      describe('when Load more is clicked', () => {
        beforeEach(async () => {
          findLoadMore().vm.$emit('click');
          await waitForPromises();
        });

        it('reads the next page from the end cursor', () => {
          expect(membersHandler).toHaveBeenLastCalledWith({
            resourceId: NAMESPACE_ID,
            roles: [],
            first: 100,
            after: 'cursor-1',
          });
        });

        it('appends the next page to the table', () => {
          expect(findUsernames()).toEqual([...ALL, 'cwu']);
        });

        it('hides Load more on the last page', () => {
          expect(findLoadMore().exists()).toBe(false);
        });

        it('resets the list instead of appending when the role filter changes', async () => {
          await submit([roleToken('ARTIFACT_ADMIN')]);
          await waitForPromises();

          expect(membersHandler).toHaveBeenLastCalledWith({
            resourceId: NAMESPACE_ID,
            roles: ['ARTIFACT_ADMIN'],
            first: 100,
          });
          expect(findUsernames()).toEqual(['agarcia', 'mlee']);
        });

        it('searches across all loaded pages', async () => {
          await submit(['casey']);

          expect(findUsernames()).toEqual(['cwu']);
        });
      });
    });

    describe('when the next page fails to load', () => {
      beforeEach(async () => {
        createComponent({ members: pagedHandler(Promise.resolve(graphQLError('unavailable'))) });
        await waitForPromises();
        findLoadMore().vm.$emit('click');
        await waitForPromises();
      });

      it('shows an alert and keeps the loaded rows', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message:
            'Members could not be loaded because the access service is unavailable. Try again later.',
          error: expect.any(Error),
          captureError: true,
        });
        expect(findUsernames()).toEqual(ALL);
      });
    });
  });

  describe.each`
    description                     | code             | message
    ${'the service is unavailable'} | ${'unavailable'} | ${'Members could not be loaded because the access service is unavailable. Try again later.'}
    ${'access is denied'}           | ${'denied'}      | ${"You don't have permission to view these members."}
    ${'the error is unknown'}       | ${'unknown'}     | ${'An error occurred loading members. Please refresh the page to try again.'}
  `('when members fail to load because $description', ({ code, message }) => {
    beforeEach(async () => {
      createComponent({ members: jest.fn().mockResolvedValue(graphQLError(code)) });
      await waitForPromises();
    });

    it('shows an alert and captures the error', () => {
      expect(createAlert).toHaveBeenCalledWith({
        message,
        error: expect.any(Error),
        captureError: true,
      });
    });

    it('does not render the invite button, stats, search, table, modals, or drawer', () => {
      expect(findInviteButton().exists()).toBe(false);
      expect(findInviteModal().exists()).toBe(false);
      expect(findRemoveModal().exists()).toBe(false);
      expect(findLeaveModal().exists()).toBe(false);
      expect(findDrawer().exists()).toBe(false);
      expect(findMemberStats().exists()).toBe(false);
      expect(findFilteredSearch().exists()).toBe(false);
      expect(findMembersTable().exists()).toBe(false);
    });
  });
});

describe('OrganizationAccessResourceApp when the counts fail to load', () => {
  let wrapper;

  beforeEach(async () => {
    wrapper = shallowMountExtended(OrganizationAccessResourceApp, {
      apolloProvider: createMockApollo(
        [
          [getOrganizationArtifactRegistry, jest.fn().mockResolvedValue(registryResponse())],
          [getResourceMembers, membersHandlerFor(ASSIGNMENTS)],
        ],
        {
          Query: {
            artifactRegistryRoleAssignmentCounts: () => {
              throw new Error('Counts failed');
            },
          },
        },
        { typePolicies: cacheConfig.typePolicies },
      ),
      provide: { organizationGid: ORGANIZATION_GID, canInviteMembers: true },
      propsData: { resourceKey: 'artifact-registry' },
      directives: { GlModal: createMockDirective('gl-modal') },
      stubs: { PageHeading },
    });
    await waitForPromises();
  });

  it('shows the generic alert', () => {
    expect(createAlert).toHaveBeenCalledWith({
      message: 'An error occurred loading members. Please refresh the page to try again.',
      error: expect.any(Error),
      captureError: true,
    });
  });

  it('hides the stats but keeps the members table', () => {
    expect(wrapper.findComponent(MemberStats).exists()).toBe(false);
    expect(wrapper.findComponent(MembersTable).props('members')).toHaveLength(ASSIGNMENTS.length);
  });
});

describe('OrganizationAccessResourceApp when the registry fails to load', () => {
  it('shows the generic alert, not the no-registry empty state', async () => {
    const wrapper = shallowMountExtended(OrganizationAccessResourceApp, {
      apolloProvider: createMockApollo([
        [getOrganizationArtifactRegistry, jest.fn().mockRejectedValue(new Error('Network error'))],
      ]),
      provide: { organizationGid: ORGANIZATION_GID, canInviteMembers: true },
      propsData: { resourceKey: 'artifact-registry' },
      directives: { GlModal: createMockDirective('gl-modal') },
      stubs: { PageHeading },
    });
    await waitForPromises();

    expect(createAlert).toHaveBeenCalledWith({
      message: 'An error occurred loading members. Please refresh the page to try again.',
      error: expect.any(Error),
      captureError: true,
    });
    expect(wrapper.findComponent(GlEmptyState).exists()).toBe(false);
  });
});
