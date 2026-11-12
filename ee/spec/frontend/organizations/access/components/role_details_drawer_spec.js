import { GlAvatarLabeled, GlAvatarLink, GlDrawer, GlIcon } from '@gitlab/ui';
import { nextTick } from 'vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import RoleDetailsDrawer from 'ee/organizations/access/components/role_details_drawer.vue';
import RoleSelector from '~/members/components/role_selector.vue';

const resource = {
  key: 'artifact-registry',
  label: 'Artifact Registry',
  roles: [
    {
      value: 'ARTIFACT_ADMIN',
      text: 'Artifact Admin',
      description: 'Manage repository configuration and access.',
      detailedDescription: 'View, create, and delete repositories.',
      accessSummary: [{ text: 'Create and configure repositories', allowed: true }],
    },
    {
      value: 'ARTIFACT_VIEWER',
      text: 'Artifact Viewer',
      description: 'Pull and browse artifacts.',
      detailedDescription: 'Browse repositories and pull artifacts. Cannot publish or delete.',
      accessSummary: [
        { text: 'Download or pull artifacts', allowed: true },
        { text: 'Push, upload, or delete artifacts', allowed: false },
      ],
    },
  ],
};

const member = {
  assignee: {
    id: 'gid://gitlab/User/5',
    name: 'Jordan Kim',
    username: 'jkim',
    avatarUrl: '/avatar.png',
    webPath: '/jkim',
  },
  role: 'ARTIFACT_VIEWER',
  createdAt: '2026-09-01T00:00:00Z',
};

describe('OrganizationAccessRoleDetailsDrawer', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = mountExtended(RoleDetailsDrawer, {
      propsData: { resource, member, ...props },
    });
  };

  const findDrawer = () => wrapper.findComponent(GlDrawer);
  const findRoleSelector = () => wrapper.findComponent(RoleSelector);
  const findUpdateButton = () => wrapper.findByTestId('update-role-button');
  const findCancelButton = () => wrapper.findByTestId('cancel-button');
  const findDescription = () => wrapper.findByTestId('drawer-role-description');
  const findSummaryItems = () => wrapper.findByTestId('drawer-permission-summary').findAll('li');
  const summaryItems = () =>
    findSummaryItems().wrappers.map((item) => {
      const icon = item.findComponent(GlIcon);
      return [icon.props('name'), icon.attributes('aria-label'), item.text()];
    });

  const selectRole = async (value) => {
    findRoleSelector().vm.$emit(
      'input',
      resource.roles.find((role) => role.value === value),
    );
    await nextTick();
  };

  describe('when there is no member', () => {
    beforeEach(() => {
      createComponent({ props: { member: null } });
    });

    it('does not render the drawer', () => {
      expect(findDrawer().exists()).toBe(false);
    });
  });

  describe('when the member role is not in the resource roles', () => {
    beforeEach(() => {
      createComponent({ props: { member: { ...member, role: 'UNKNOWN_ROLE' } } });
    });

    it('does not render the description or permission summary', () => {
      expect(findDescription().exists()).toBe(false);
      expect(wrapper.findByTestId('drawer-permission-summary').exists()).toBe(false);
      expect(wrapper.text()).not.toContain('Permission summary');
      expect(wrapper.findByTestId('view-permissions-button').exists()).toBe(false);
    });
  });

  describe('when a member is set', () => {
    beforeEach(() => {
      createComponent();
    });

    it('opens the drawer with the title', () => {
      expect(findDrawer().props('open')).toBe(true);
      expect(findDrawer().text()).toContain('Role details');
    });

    it('renders the account avatar, name, and username linked to the user', () => {
      expect(wrapper.findComponent(GlAvatarLink).attributes('href')).toBe('/jkim');
      expect(wrapper.findComponent(GlAvatarLabeled).props()).toMatchObject({
        size: 48,
        src: '/avatar.png',
        label: 'Jordan Kim',
        subLabel: '@jkim',
      });
    });

    it('renders the role selector with the resource roles and the member role', () => {
      const items = [
        {
          value: 'ARTIFACT_ADMIN',
          text: 'Artifact Admin',
          description: 'Manage repository configuration and access.',
        },
        {
          value: 'ARTIFACT_VIEWER',
          text: 'Artifact Viewer',
          description: 'Pull and browse artifacts.',
        },
      ];

      expect(findRoleSelector().props('roles')).toEqual({ formatted: items, flatten: items });
      expect(findRoleSelector().props('value').value).toBe('ARTIFACT_VIEWER');
    });

    it('labels the role selector with the Role heading', () => {
      const toggleId = 'organization-access-role-details-role-toggle';

      expect(findRoleSelector().props('toggleId')).toBe(toggleId);
      expect(wrapper.find(`label[for="${toggleId}"]`).text()).toBe('Role');
    });

    it('renders the detailed role description', () => {
      expect(findDescription().text()).toBe(
        'Browse repositories and pull artifacts. Cannot publish or delete.',
      );
    });

    it('renders the permission summary with allowed and not allowed icons', () => {
      expect(wrapper.text()).toContain('Permission summary');
      expect(summaryItems()).toEqual([
        ['check', 'Allowed', 'Download or pull artifacts'],
        ['close', 'Not allowed', 'Push, upload, or delete artifacts'],
      ]);
    });

    it('renders the View permissions link', () => {
      const button = wrapper.findByTestId('view-permissions-button');

      expect(button.text()).toBe('View permissions');
      expect(button.attributes()).toMatchObject({
        href: '/help/user/permissions',
        target: '_blank',
      });
    });

    it('does not render the footer buttons', () => {
      expect(findUpdateButton().exists()).toBe(false);
      expect(findCancelButton().exists()).toBe(false);
    });

    it('emits close when the drawer closes', () => {
      findDrawer().vm.$emit('close');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });
  });

  describe('when a different role is selected', () => {
    beforeEach(async () => {
      createComponent();
      await selectRole('ARTIFACT_ADMIN');
    });

    it('shows the selected role description and permission summary', () => {
      expect(findDescription().text()).toBe('View, create, and delete repositories.');
      expect(summaryItems()).toEqual([['check', 'Allowed', 'Create and configure repositories']]);
    });

    it('shows Update role and Cancel', () => {
      expect(findUpdateButton().text()).toBe('Update role');
      expect(findCancelButton().text()).toBe('Cancel');
    });

    it('emits update-role with the member and role on Update role', async () => {
      await findUpdateButton().trigger('click');

      expect(wrapper.emitted('update-role')).toEqual([[{ member, role: 'ARTIFACT_ADMIN' }]]);
    });

    it('resets the role and hides the buttons on Cancel', async () => {
      await findCancelButton().trigger('click');

      expect(findRoleSelector().props('value').value).toBe('ARTIFACT_VIEWER');
      expect(findUpdateButton().exists()).toBe(false);
    });

    it('hides the buttons after the member role is saved', async () => {
      await wrapper.setProps({ member: { ...member, role: 'ARTIFACT_ADMIN' } });

      expect(findRoleSelector().props('value').value).toBe('ARTIFACT_ADMIN');
      expect(findUpdateButton().exists()).toBe(false);
    });

    it('keeps the selection when the parent passes a copy of the same member', async () => {
      await wrapper.setProps({ member: { ...member } });

      expect(findRoleSelector().props('value').value).toBe('ARTIFACT_ADMIN');
      expect(findUpdateButton().exists()).toBe(true);
    });

    it('resets the selection when another member is opened', async () => {
      await wrapper.setProps({
        member: {
          ...member,
          assignee: { ...member.assignee, id: 'gid://gitlab/User/1' },
        },
      });

      expect(findRoleSelector().props('value').value).toBe('ARTIFACT_VIEWER');
      expect(findUpdateButton().exists()).toBe(false);
    });
  });
});
