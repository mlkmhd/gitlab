import { GlButton, GlModal } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import Vue, { nextTick } from 'vue';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import DeployFreezeModal from '~/deploy_freeze/components/deploy_freeze_modal.vue';
import { useDeployFreeze } from '~/deploy_freeze/store';
import TimezoneDropdown from '~/vue_shared/components/timezone_dropdown/timezone_dropdown.vue';
import { freezePeriodsFixture } from '../helpers';
import { timezoneDataFixture } from '../../vue_shared/components/timezone_dropdown/helpers';

Vue.use(PiniaVuePlugin);

describe('Deploy freeze modal', () => {
  let wrapper;
  let pinia;
  let store;

  beforeEach(() => {
    pinia = createTestingPinia();
    store = useDeployFreeze();
    store.projectId = '8';
    store.timezoneData = timezoneDataFixture;
    wrapper = shallowMount(DeployFreezeModal, {
      attachTo: document.body,
      stubs: {
        GlModal,
      },
      pinia,
    });
  });

  const findModal = () => wrapper.findComponent(GlModal);
  const submitDeployFreezeButton = () => findModal().findAllComponents(GlButton).at(1);

  // eslint-disable-next-line max-params
  const setInput = (freezeStartCron, freezeEndCron, selectedTimezone, id = '') => {
    store.freezeStartCron = freezeStartCron;
    store.freezeEndCron = freezeEndCron;
    store.selectedTimezone = selectedTimezone;
    store.selectedTimezoneIdentifier = selectedTimezone;
    store.selectedId = id;

    wrapper.find('#deploy-freeze-start').trigger('input');
    wrapper.find('#deploy-freeze-end').trigger('input');
    wrapper.findComponent(TimezoneDropdown).trigger('input');
  };

  describe('Basic interactions', () => {
    it.each`
      index | stateKey
      ${0}  | ${'freezeStartCron'}
      ${1}  | ${'freezeEndCron'}
    `('writes cron input $index to $stateKey in the store', async ({ index, stateKey }) => {
      wrapper.findAllComponents({ name: 'GlFormInput' }).at(index).vm.$emit('input', '5 0 * 8 *');
      await nextTick();

      expect(store[stateKey]).toBe('5 0 * 8 *');
    });

    it('resets the modal when canceled', () => {
      findModal().vm.$emit('canceled');

      expect(store.resetModal).toHaveBeenCalledTimes(1);
    });

    it('button is disabled when freeze period is invalid', () => {
      expect(submitDeployFreezeButton().attributes('disabled')).toBeDefined();
    });
  });

  describe('Adding a new deploy freeze', () => {
    const { freeze_start, freeze_end, cron_timezone } = freezePeriodsFixture[0];

    beforeEach(() => {
      setInput(freeze_start, freeze_end, cron_timezone);
    });

    it('button is enabled when valid freeze period settings are present', () => {
      expect(submitDeployFreezeButton().attributes('disabled')).toBeUndefined();
    });

    it('should display Add deploy freeze', () => {
      expect(findModal().props('title')).toBe('Add deploy freeze');
      expect(submitDeployFreezeButton().text()).toBe('Add deploy freeze');
    });

    it('should call the addFreezePeriod action', () => {
      findModal().vm.$emit('primary');

      expect(store.addFreezePeriod).toHaveBeenCalledTimes(1);
      expect(store.updateFreezePeriod).not.toHaveBeenCalled();
    });
  });

  describe('Validations', () => {
    describe('when the cron state is invalid', () => {
      beforeEach(() => {
        setInput('invalid cron', 'invalid cron', 'invalid timezone');
      });

      it('disables the add deploy freeze button', () => {
        expect(submitDeployFreezeButton().attributes('disabled')).toBeDefined();
      });
    });

    describe('when the cron state is valid', () => {
      beforeEach(() => {
        const { freeze_start, freeze_end, cron_timezone } = freezePeriodsFixture[0];
        setInput(freeze_start, freeze_end, cron_timezone);
      });

      it('does not disable the submit button', () => {
        expect(submitDeployFreezeButton().attributes('disabled')).toBeUndefined();
      });
    });
  });

  describe('Editing an existing deploy freeze', () => {
    const { freeze_start, freeze_end, cron_timezone, id } = freezePeriodsFixture[0];

    beforeEach(() => {
      setInput(freeze_start, freeze_end, cron_timezone, id);
    });

    it('should display Edit deploy freeze', () => {
      expect(findModal().props('title')).toBe('Edit deploy freeze');
      expect(submitDeployFreezeButton().text()).toBe('Save deploy freeze');
    });

    it('should call the updateFreezePeriod action', () => {
      findModal().vm.$emit('primary');

      expect(store.updateFreezePeriod).toHaveBeenCalledTimes(1);
      expect(store.addFreezePeriod).not.toHaveBeenCalled();
    });
  });
});
