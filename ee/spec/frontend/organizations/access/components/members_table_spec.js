import {
  GlAvatarLabeled,
  GlAvatarLink,
  GlDisclosureDropdown,
  GlEmptyState,
  GlLoadingIcon,
  GlTableLite,
} from '@gitlab/ui';
import { useFakeRequestAnimationFrame } from 'helpers/fake_request_animation_frame';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import MembersTable from 'ee/organizations/access/components/members_table.vue';
import CreatedAt from '~/members/components/table/created_at.vue';

const resource = {
  key: 'artifact-registry',
  label: 'Artifact Registry',
  noMembersDescription: 'Assign an Artifact role to a user to give them access to this resource.',
  roles: [
    { value: 'ARTIFACT_ADMIN', text: 'Artifact Admin' },
    { value: 'ARTIFACT_VIEWER', text: 'Artifact Viewer' },
  ],
};

const members = [
  {
    assignee: {
      id: 'gid://gitlab/User/1',
      name: 'Alex Garcia',
      username: 'agarcia',
      avatarUrl: 'https://example.com/avatar.png',
      webPath: '/agarcia',
    },
    role: 'ARTIFACT_ADMIN',
    createdAt: '2026-08-14T10:00:00Z',
    userPermissions: { updateRole: true, removeMember: true, leave: false },
  },
  {
    assignee: {
      id: 'gid://gitlab/User/2',
      name: 'Jordan Kim',
      username: 'jkim',
      avatarUrl: null,
      webPath: '/jkim',
    },
    role: 'ARTIFACT_VIEWER',
    createdAt: '2026-09-28T16:45:00Z',
    userPermissions: { updateRole: true, removeMember: false, leave: true },
  },
];

describe('OrganizationAccessMembersTable', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = mountExtended(MembersTable, {
      propsData: { resource, members, ...props },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
    });
  };

  const findTable = () => wrapper.findComponent(GlTableLite);
  const findRows = () => wrapper.findAll('tbody tr');
  const findHeaders = () => wrapper.findAll('thead th').wrappers.map((th) => th.text());
  const findMemberRoleButtons = () => wrapper.findAllByTestId('member-role-button');
  const findMemberRoleButton = () => wrapper.findByTestId('member-role-button');
  const findMemberRoleText = () => wrapper.findByTestId('member-role-text');

  describe('with members', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the Member, Role, Access granted, and Actions columns only', () => {
      expect(findHeaders()).toEqual(['Member', 'Role', 'Access granted', 'Actions']);
    });

    it('renders a row per member', () => {
      expect(findRows()).toHaveLength(2);
    });

    it('renders the member avatar, name, and username linked to the user', () => {
      const row = findRows().at(0);

      expect(row.findComponent(GlAvatarLink).attributes('href')).toBe('/agarcia');
      expect(row.findComponent(GlAvatarLabeled).props()).toMatchObject({
        size: 32,
        src: 'https://example.com/avatar.png',
        label: 'Alex Garcia',
        subLabel: '@agarcia',
      });
    });

    it('renders the role label from the resource config', () => {
      expect(findMemberRoleButtons().wrappers.map((cell) => cell.text())).toEqual([
        'Artifact Admin',
        'Artifact Viewer',
      ]);
    });

    it('emits select-member with the row when a role is clicked', async () => {
      await findMemberRoleButtons().at(1).trigger('click');

      expect(wrapper.emitted('select-member')).toEqual([[members[1]]]);
    });

    it('renders the role as a link, not plain text, when the role can be changed', () => {
      expect(findMemberRoleButtons()).toHaveLength(2);
      expect(findMemberRoleText().exists()).toBe(false);
    });

    it('renders the granted date', () => {
      const createdAt = findRows().at(0).findComponent(CreatedAt);

      expect(createdAt.props('date')).toBe('2026-08-14T10:00:00Z');
      expect(createdAt.text()).toBe('Aug 14, 2026');
    });
  });

  describe('when the role cannot be changed', () => {
    it.each`
      description               | userPermissions
      ${'updateRole is false'}  | ${{ updateRole: false, removeMember: true, leave: false }}
      ${'no permissions field'} | ${undefined}
      ${'null permissions'}     | ${null}
    `('renders the role as plain text when $description', async ({ userPermissions }) => {
      createComponent({ props: { members: [{ ...members[0], userPermissions }] } });

      expect(findMemberRoleButton().exists()).toBe(false);
      expect(findMemberRoleText().text()).toBe('Artifact Admin');

      await findMemberRoleText().trigger('click');

      expect(wrapper.emitted('select-member')).toBeUndefined();
    });

    it('leaves Edit role out of the Actions menu', () => {
      createComponent({
        props: {
          members: [
            {
              ...members[0],
              userPermissions: { updateRole: false, removeMember: true, leave: false },
            },
          ],
        },
      });

      expect(
        findRows()
          .at(0)
          .findComponent(GlDisclosureDropdown)
          .props('items')
          .map(({ text }) => text),
      ).toEqual(['Remove member']);
    });
  });

  describe('when a member has no Artifact role', () => {
    beforeEach(() => {
      createComponent({
        props: {
          members: [
            {
              ...members[0],
              role: null,
              userPermissions: { updateRole: false, removeMember: false, leave: false },
            },
          ],
        },
      });
    });

    it('renders the role as Organization role text, not a link', () => {
      expect(findMemberRoleButton().exists()).toBe(false);
      expect(findMemberRoleText().text()).toBe('Organization role');
    });

    it('renders no actions', () => {
      expect(findRows().at(0).findComponent(GlDisclosureDropdown).exists()).toBe(false);
    });
  });

  describe('when a member has no Artifact role but the role can be changed', () => {
    it('renders Organization role as text, not a link', () => {
      createComponent({ props: { members: [{ ...members[0], role: null }] } });

      expect(findMemberRoleButton().exists()).toBe(false);
      expect(findMemberRoleText().text()).toBe('Organization role');
    });
  });

  describe('row actions', () => {
    const findActions = (index) => findRows().at(index).findComponent(GlDisclosureDropdown);
    const actionTexts = (index) =>
      findActions(index)
        .props('items')
        .map(({ text }) => text);
    const runAction = (index, text) =>
      findActions(index).vm.$emit(
        'action',
        findActions(index)
          .props('items')
          .find((item) => item.text === text),
      );

    beforeEach(() => {
      createComponent();
    });

    it('renders an Actions menu per row', () => {
      expect(findActions(0).props()).toMatchObject({
        toggleText: 'Actions',
        textSrOnly: true,
        icon: 'ellipsis_v',
        category: 'tertiary',
        noCaret: true,
      });
      expect(getBinding(findActions(0).element, 'gl-tooltip').value).toBe('Actions');
    });

    it('offers Edit role and Remove member when the row allows them', () => {
      expect(actionTexts(0)).toEqual(['Edit role', 'Remove member']);
      expect(findActions(0).props('items')[1].variant).toBe('danger');
    });

    it('offers Edit role and Leave when the row allows them', () => {
      expect(actionTexts(1)).toEqual(['Edit role', 'Leave']);
      expect(findActions(1).props('items')[1].variant).toBe('danger');
    });

    it.each`
      description               | userPermissions
      ${'no permissions'}       | ${{ updateRole: false, removeMember: false, leave: false }}
      ${'no permissions field'} | ${undefined}
      ${'null permissions'}     | ${null}
    `('renders no Actions menu for a row with $description', ({ userPermissions }) => {
      createComponent({ props: { members: [{ ...members[0], userPermissions }] } });

      expect(findActions(0).exists()).toBe(false);
    });

    it.each`
      index | text               | event
      ${0}  | ${'Edit role'}     | ${'select-member'}
      ${0}  | ${'Remove member'} | ${'remove-member'}
      ${1}  | ${'Leave'}         | ${'leave'}
    `('emits $event with the row for $text', ({ index, text, event }) => {
      runAction(index, text);

      expect(wrapper.emitted(event)).toEqual([[members[index]]]);
    });
  });

  describe('after a member is prepended', () => {
    useFakeRequestAnimationFrame();

    // Click the rendered item so the dropdown's real listener runs, not a direct $emit.
    const clickAction = (index, text) =>
      findRows()
        .at(index)
        .findAll('[data-testid="disclosure-dropdown-item"]')
        .filter((item) => item.text() === text)
        .at(0)
        .find('button')
        .trigger('click');

    const invited = {
      ...members[0],
      assignee: { ...members[0].assignee, id: 'gid://gitlab/User/9', username: 'cwu' },
    };

    beforeEach(async () => {
      // The mock tooltip directive stops setProps from re-rendering under Vue 3.
      wrapper = mountExtended(MembersTable, { propsData: { resource, members } });
      await wrapper.setProps({ members: [invited, ...members] });
    });

    it('renders the prepended member as a new first row', () => {
      expect(findRows()).toHaveLength(members.length + 1);
      expect(findRows().at(0).text()).toContain('cwu');
    });

    it('emits select-member with the clicked row', async () => {
      await wrapper.findAllByTestId('member-role-button').at(1).trigger('click');

      expect(wrapper.emitted('select-member')).toEqual([[members[0]]]);
    });

    it.each`
      index | text               | event              | member
      ${1}  | ${'Remove member'} | ${'remove-member'} | ${members[0]}
      ${2}  | ${'Leave'}         | ${'leave'}         | ${members[1]}
      ${0}  | ${'Remove member'} | ${'remove-member'} | ${invited}
    `(
      'emits $event with row $index from the Actions menu',
      async ({ index, text, event, member }) => {
        await clickAction(index, text);

        expect(wrapper.emitted(event)).toEqual([[member]]);
      },
    );
  });

  it('renders a loading icon instead of the table when loading', () => {
    createComponent({ props: { loading: true } });

    expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(true);
    expect(findTable().exists()).toBe(false);
  });

  it.each`
    description                                  | hasActiveFilters | illustrationName     | title                        | text
    ${'there are no members'}                    | ${false}         | ${'empty-user-md'}   | ${'Grant access to members'} | ${'Assign an Artifact role to a user to give them access to this resource.'}
    ${'filters are active and no members match'} | ${true}          | ${'empty-search-md'} | ${'No results found'}        | ${'Edit your search and try again.'}
  `(
    'renders the empty state when $description',
    ({ hasActiveFilters, illustrationName, title, text }) => {
      createComponent({ props: { members: [], hasActiveFilters } });

      expect(wrapper.findComponent(GlEmptyState).props()).toMatchObject({
        illustrationName,
        title,
        description: text,
      });
      expect(findTable().exists()).toBe(false);
    },
  );
});
