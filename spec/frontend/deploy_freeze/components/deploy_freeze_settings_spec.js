import { shallowMount } from '@vue/test-utils';
import Vue from 'vue';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import DeployFreezeModal from '~/deploy_freeze/components/deploy_freeze_modal.vue';
import DeployFreezeSettings from '~/deploy_freeze/components/deploy_freeze_settings.vue';
import DeployFreezeTable from '~/deploy_freeze/components/deploy_freeze_table.vue';
import { useDeployFreeze } from '~/deploy_freeze/store';
import { timezoneDataFixture } from '../../vue_shared/components/timezone_dropdown/helpers';

Vue.use(PiniaVuePlugin);

describe('Deploy freeze settings', () => {
  let wrapper;
  let pinia;

  beforeEach(() => {
    pinia = createTestingPinia();
    const store = useDeployFreeze();
    store.projectId = '8';
    store.timezoneData = timezoneDataFixture;
    wrapper = shallowMount(DeployFreezeSettings, {
      pinia,
    });
  });

  describe('Deploy freeze table contains components', () => {
    it('contains deploy freeze table', () => {
      expect(wrapper.findComponent(DeployFreezeTable).exists()).toBe(true);
    });

    it('contains deploy freeze modal', () => {
      expect(wrapper.findComponent(DeployFreezeModal).exists()).toBe(true);
    });
  });
});
