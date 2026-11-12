import { GlFormRadio, GlFormRadioGroup, GlModal, GlSprintf } from '@gitlab/ui';
import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RemoveMemberModal from 'ee/organizations/access/components/remove_member_modal.vue';

const resource = { key: 'artifact-registry', label: 'Artifact Registry' };

const member = {
  assignee: { id: 'gid://gitlab/User/5', name: 'Jordan Kim', username: 'jkim' },
  role: 'ARTIFACT_VIEWER',
  directRepositoryCount: null,
};

describe('OrganizationAccessRemoveMemberModal', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(RemoveMemberModal, {
      propsData: { resource, member, ...props },
      stubs: { GlFormRadio, GlSprintf },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findRadioGroup = () => wrapper.findComponent(GlFormRadioGroup);
  const findRadios = () => wrapper.findAllComponents(GlFormRadio);
  const isPrimaryDisabled = () => findModal().props('actionPrimary').attributes.disabled;

  describe('when there is no member', () => {
    beforeEach(() => {
      createComponent({ props: { member: null } });
    });

    it('hides the modal', () => {
      expect(findModal().props('visible')).toBe(false);
    });
  });

  describe('when the member has no direct repository access', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows the modal with the title and actions', () => {
      expect(findModal().props()).toMatchObject({
        visible: true,
        title: 'Remove member',
        actionPrimary: { text: 'Remove member', attributes: { variant: 'danger' } },
        actionCancel: { text: 'Cancel' },
      });
    });

    it('shows only the confirm text', () => {
      expect(findModal().text()).toBe(
        'Are you sure you want to remove Jordan Kim from Artifact Registry?',
      );
      expect(findRadioGroup().exists()).toBe(false);
    });

    it('enables Remove member', () => {
      expect(isPrimaryDisabled()).toBe(false);
    });

    it('emits remove with the member and no scope', () => {
      findModal().vm.$emit('primary');

      expect(wrapper.emitted('remove')).toEqual([[{ member, removalScope: null }]]);
    });

    it('emits close when hidden', () => {
      findModal().vm.$emit('hidden');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });
  });

  describe.each`
    count | countText           | helpText
    ${1}  | ${'1 repository'}   | ${'User keeps direct access to 1 repository'}
    ${6}  | ${'6 repositories'} | ${'User keeps direct access to 6 repositories'}
  `(
    'when the member has direct access to $count repositories',
    ({ count, countText, helpText }) => {
      const directMember = { ...member, directRepositoryCount: count };

      beforeEach(() => {
        createComponent({ props: { member: directMember } });
      });

      it('shows the pluralized count', () => {
        const message = wrapper.findByTestId('direct-access-message');

        expect(message.text()).toBe(`This user has direct access to ${countText}.`);
        expect(message.find('strong').text()).toBe(countText);
      });

      it('labels the removal scope choice', () => {
        expect(findRadioGroup().attributes('aria-label')).toBe('Choose which access to remove');
      });

      it('offers both removal scopes with help text', () => {
        expect(findRadios().wrappers.map((radio) => radio.props('value'))).toEqual([
          'direct_and_inherited',
          'inherited_only',
        ]);
        expect(findRadios().at(0).text()).toContain('Remove direct and inherited access');
        expect(findRadios().at(0).text()).toContain(
          'User access is removed everywhere in Artifact Registry',
        );
        expect(findRadios().at(1).text()).toContain('Remove only inherited access');
        expect(findRadios().at(1).text()).toContain(helpText);
      });

      it('disables Remove member until a scope is picked', async () => {
        expect(isPrimaryDisabled()).toBe(true);

        findRadioGroup().vm.$emit('input', 'inherited_only');
        await nextTick();

        expect(isPrimaryDisabled()).toBe(false);
      });

      it('emits remove with the picked scope', async () => {
        findRadioGroup().vm.$emit('input', 'direct_and_inherited');
        await nextTick();
        findModal().vm.$emit('primary');

        expect(wrapper.emitted('remove')).toEqual([
          [{ member: directMember, removalScope: 'direct_and_inherited' }],
        ]);
      });
    },
  );

  describe('when the modal reopens for another member', () => {
    beforeEach(async () => {
      createComponent({ props: { member: { ...member, directRepositoryCount: 6 } } });
      findRadioGroup().vm.$emit('input', 'inherited_only');
      await nextTick();
      await wrapper.setProps({ member: null });
      await wrapper.setProps({ member: { ...member, directRepositoryCount: 2 } });
    });

    it('resets the picked scope', () => {
      expect(findRadioGroup().props('checked')).toBeNull();
      expect(isPrimaryDisabled()).toBe(true);
    });
  });
});
