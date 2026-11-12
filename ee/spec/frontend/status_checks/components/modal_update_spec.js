import { shallowMount } from '@vue/test-utils';
import Vue from 'vue';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import ModalUpdate from 'ee/status_checks/components/modal_update.vue';
import SharedModal from 'ee/status_checks/components/shared_modal.vue';
import { useStatusChecks } from 'ee/status_checks/store';
import { TEST_PROTECTED_BRANCHES } from 'ee_jest/vue_shared/components/branches_selector/mock_data';

Vue.use(PiniaVuePlugin);

const projectId = '1';
const statusChecksPath = '/api/v4/projects/1/external_approval_rules';
const modalId = 'status-checks-update-modal';
const title = 'Update status check';
const statusCheck = {
  externalUrl: 'https://foo.com',
  id: 1,
  name: 'Foo',
  protectedBranches: TEST_PROTECTED_BRANCHES,
};

describe('Modal update', () => {
  let wrapper;
  let pinia;
  let store;

  const createWrapper = () => {
    pinia = createTestingPinia();
    store = useStatusChecks();
    store.$patch({ settings: { projectId, statusChecksPath } });

    wrapper = shallowMount(ModalUpdate, {
      propsData: {
        statusCheck,
      },
      pinia,
    });
  };

  beforeEach(() => {
    createWrapper();
  });

  const findModal = () => wrapper.findComponent(SharedModal);

  describe('Modal', () => {
    it('sets the modals props', () => {
      expect(findModal().props()).toStrictEqual({
        action: expect.any(Function),
        modalId,
        title,
        statusCheck,
      });
    });

    it('passes the putStatusCheck action', () => {
      findModal().props('action')(statusCheck);

      expect(store.putStatusCheck).toHaveBeenCalledWith(statusCheck);
    });
  });
});
