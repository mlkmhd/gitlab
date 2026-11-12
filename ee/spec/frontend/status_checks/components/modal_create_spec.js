import { GlButton } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import Vue from 'vue';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import ModalCreate from 'ee/status_checks/components/modal_create.vue';
import SharedModal from 'ee/status_checks/components/shared_modal.vue';
import { useStatusChecks } from 'ee/status_checks/store';
import { stubComponent } from 'helpers/stub_component';

Vue.use(PiniaVuePlugin);

const projectId = '1';
const statusChecksPath = '/api/v4/projects/1/external_approval_rules';
const modalId = 'status-checks-create-modal';
const title = 'Add status check';

describe('Modal create', () => {
  let wrapper;
  let pinia;
  let store;

  const createWrapper = ({ stubs = {} } = {}) => {
    pinia = createTestingPinia();
    store = useStatusChecks();
    store.$patch({ settings: { projectId, statusChecksPath } });

    wrapper = shallowMount(ModalCreate, {
      pinia,
      stubs: {
        GlButton,
        ...stubs,
      },
    });
  };

  beforeEach(() => {
    createWrapper();
  });

  const findAddBtn = () => wrapper.findComponent(GlButton);
  const findModal = () => wrapper.findComponent(SharedModal);

  describe('Add button', () => {
    it('renders', () => {
      expect(findAddBtn().text()).toBe('Add status check');
    });

    it('opens the modal', () => {
      const mockDeleteModalShow = jest.fn();
      createWrapper({
        stubs: {
          SharedModal: stubComponent(SharedModal, {
            methods: {
              show: mockDeleteModalShow,
            },
          }),
        },
      });
      findAddBtn().trigger('click');
      expect(mockDeleteModalShow).toHaveBeenCalled();
    });
  });

  describe('Modal', () => {
    it('sets the modals props', () => {
      expect(findModal().props()).toStrictEqual({
        action: expect.any(Function),
        modalId,
        title,
        statusCheck: undefined,
      });
    });

    it('passes the postStatusCheck action', () => {
      const payload = { name: 'Foo', externalUrl: 'https://foo.com' };

      findModal().props('action')(payload);

      expect(store.postStatusCheck).toHaveBeenCalledWith(payload);
    });
  });
});
