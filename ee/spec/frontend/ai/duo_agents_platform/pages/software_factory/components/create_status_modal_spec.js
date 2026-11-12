import { nextTick } from 'vue';
import { GlModal, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import CreateStatusModal from 'ee/ai/duo_agents_platform/pages/software_factory/components/create_status_modal.vue';

const lifecycles = [
  { id: 'gid://gitlab/Lifecycle/1', name: 'Default' },
  { id: 'gid://gitlab/Lifecycle/2', name: 'Engineering' },
];

describe('CreateStatusModal', () => {
  let wrapper;

  const createComponent = async (props = {}) => {
    wrapper = shallowMountExtended(CreateStatusModal, {
      propsData: {
        visible: true,
        groupName: 'Group',
        initialName: 'Verification',
        initialCategory: 'IN_PROGRESS',
        lifecycles: [lifecycles[0]],
        initialLifecycleId: lifecycles[0].id,
        existingNames: ['To do', 'Done'],
        ...props,
      },
      stubs: { GlSprintf },
    });

    wrapper.findComponent(GlModal).vm.$emit('show');
    await nextTick();
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findLifecycle = () => wrapper.findComponentByTestId('create-status-lifecycle');
  const isSubmitDisabled = () => findModal().props('actionPrimary').attributes.disabled;

  let preventDefault;

  const submit = () => {
    preventDefault = jest.fn();
    findModal().vm.$emit('primary', { preventDefault });
  };

  describe('with a valid status', () => {
    beforeEach(() => createComponent());

    it('submits the name, category, category colour and lifecycle', () => {
      submit();

      expect(wrapper.emitted('submit')).toEqual([
        [
          {
            name: 'Verification',
            category: 'IN_PROGRESS',
            color: '#1f73ca',
            lifecycleId: lifecycles[0].id,
          },
        ],
      ]);
    });

    it('stays open, so that a server error lands next to the form', () => {
      submit();

      expect(preventDefault).toHaveBeenCalled();
    });

    it('does not ask for a lifecycle', () => {
      expect(findLifecycle().exists()).toBe(false);
    });
  });

  describe('when the group has more than one lifecycle', () => {
    beforeEach(() => createComponent({ lifecycles }));

    it('asks which one the status belongs to', () => {
      expect(findLifecycle().exists()).toBe(true);
    });
  });

  describe('when the lifecycles have not loaded yet', () => {
    beforeEach(() => createComponent({ lifecycles: [], initialLifecycleId: null }));

    it('does not let the author create a status', () => {
      expect(isSubmitDisabled()).toBe(true);
    });

    describe('once they arrive', () => {
      beforeEach(() => wrapper.setProps({ lifecycles: [lifecycles[0]] }));

      it('falls back to the first one', async () => {
        submit();
        await nextTick();

        expect(wrapper.emitted('submit')[0][0]).toMatchObject({ lifecycleId: lifecycles[0].id });
      });
    });
  });

  describe('while the status is being saved', () => {
    beforeEach(() => createComponent({ isSaving: true }));

    it('does not let the author cancel or submit it a second time', () => {
      expect(findModal().props('actionCancel').attributes.disabled).toBe(true);

      submit();

      expect(wrapper.emitted('submit')).toBeUndefined();
    });

    it('does not let the author close it', () => {
      const event = { preventDefault: jest.fn() };

      findModal().vm.$emit('hide', event);

      expect(event.preventDefault).toHaveBeenCalled();
      expect(wrapper.emitted('hide')).toBeUndefined();
    });
  });

  describe('when the author closes it', () => {
    beforeEach(() => createComponent());

    it('passes the close on to the page', () => {
      findModal().vm.$emit('hide', { preventDefault: jest.fn() });

      expect(wrapper.emitted('hide')).toHaveLength(1);
    });
  });

  describe('when the name is already taken, ignoring case', () => {
    beforeEach(() => createComponent({ initialName: 'done' }));

    it('does not let the author create it', () => {
      expect(isSubmitDisabled()).toBe(true);

      submit();

      expect(wrapper.emitted('submit')).toBeUndefined();
    });
  });

  describe('when the name is blank', () => {
    beforeEach(async () => {
      await createComponent();
      wrapper.findComponentByTestId('create-status-name').vm.$emit('input', '   ');
      await nextTick();
    });

    it('does not let the author create it', () => {
      expect(isSubmitDisabled()).toBe(true);
    });
  });

  describe('when the server rejects the status', () => {
    beforeEach(() => createComponent({ error: 'Name has already been taken' }));

    it('shows the error', () => {
      expect(wrapper.findByTestId('create-status-error').text()).toBe(
        'Name has already been taken',
      );
    });
  });
});
