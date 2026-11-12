import { GlModal } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import LeaveModal from 'ee/organizations/access/components/leave_modal.vue';

const resource = { key: 'artifact-registry', label: 'Artifact Registry' };

const member = {
  assignee: { id: 'gid://gitlab/User/5', name: 'Jordan Kim', username: 'jkim' },
  role: 'ARTIFACT_VIEWER',
};

describe('OrganizationAccessLeaveModal', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(LeaveModal, {
      propsData: { resource, member, ...props },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);

  it('hides the modal when there is no member', () => {
    createComponent({ props: { member: null } });

    expect(findModal().props('visible')).toBe(false);
  });

  describe('when a member is set', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows the modal with the resource in the title and body', () => {
      expect(findModal().props()).toMatchObject({
        visible: true,
        title: 'Leave "Artifact Registry"',
        actionPrimary: { text: 'Leave', attributes: { variant: 'danger' } },
        actionCancel: { text: 'Cancel' },
      });
      expect(findModal().text()).toBe('Are you sure you want to leave "Artifact Registry"?');
    });

    it('emits leave with the member on Leave', () => {
      findModal().vm.$emit('primary');

      expect(wrapper.emitted('leave')).toEqual([[{ member }]]);
    });

    it('emits close when hidden', () => {
      findModal().vm.$emit('hidden');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });
  });
});
