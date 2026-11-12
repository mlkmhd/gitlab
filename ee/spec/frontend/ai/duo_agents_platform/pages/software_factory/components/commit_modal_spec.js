import { nextTick } from 'vue';
import { GlModal } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useFakeDate } from 'helpers/fake_date';
import CommitModal from 'ee/ai/duo_agents_platform/pages/software_factory/components/commit_modal.vue';

describe('CommitModal', () => {
  let wrapper;

  useFakeDate(2026, 9, 22);

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(CommitModal, {
      propsData: { visible: true, defaultBranch: 'main', ...props },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findMessageInput = () => wrapper.findComponentByTestId('commit-message-input');
  const findBranchInput = () => wrapper.findComponentByTestId('commit-branch-input');

  describe('when committing to the default branch', () => {
    beforeEach(() => {
      createComponent();
    });

    it('does not ask for a branch, and submits only the commit message', () => {
      expect(findBranchInput().exists()).toBe(false);

      findModal().vm.$emit('primary');

      expect(wrapper.emitted('submit')).toEqual([
        [{ message: 'Update DAP Software Factory configuration', branch: '' }],
      ]);
    });
  });

  describe('when opening a merge request', () => {
    beforeEach(() => {
      createComponent({ openMergeRequest: true });
    });

    it('submits the message and a new branch', () => {
      findModal().vm.$emit('primary');

      expect(wrapper.emitted('submit')).toEqual([
        [
          {
            message: 'Update DAP Software Factory configuration',
            branch: `dap-factory-config-${Date.now()}`,
          },
        ],
      ]);
    });
  });

  describe('when the commit message is blank', () => {
    beforeEach(async () => {
      createComponent();
      findMessageInput().vm.$emit('input', '  ');
      await nextTick();
    });

    it('does not let the author commit', () => {
      expect(findModal().props('actionPrimary').attributes.disabled).toBe(true);

      findModal().vm.$emit('primary');

      expect(wrapper.emitted('submit')).toBeUndefined();
    });
  });

  describe('when the modal is opened again', () => {
    beforeEach(async () => {
      createComponent();
      findMessageInput().vm.$emit('input', 'Half-written message');
      findModal().vm.$emit('show');
      await nextTick();
    });

    it('starts from the default commit message again', () => {
      expect(findMessageInput().props('value')).toBe('Update DAP Software Factory configuration');
    });
  });

  describe('when the configuration has errors', () => {
    beforeEach(() => {
      createComponent({ errorCount: 2 });
    });

    it('warns that sync will not apply it', () => {
      expect(wrapper.findByTestId('commit-modal-errors').exists()).toBe(true);
    });
  });
});
