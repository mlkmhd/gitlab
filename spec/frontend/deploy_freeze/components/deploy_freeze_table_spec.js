import { GlModal, GlSprintf } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import { shallowMountExtended, mountExtended } from 'helpers/vue_test_utils_helper';
import DeployFreezeTable from '~/deploy_freeze/components/deploy_freeze_table.vue';
import { useDeployFreeze } from '~/deploy_freeze/store';
import { convertObjectPropsToCamelCase } from '~/lib/utils/common_utils';
import { freezePeriodsFixture } from '../helpers';
import { timezoneDataFixture } from '../../vue_shared/components/timezone_dropdown/helpers';

Vue.use(PiniaVuePlugin);

describe('Deploy freeze table', () => {
  let wrapper;
  let pinia;
  let store;

  const createComponent = (mountFn = mountExtended) => {
    pinia = createTestingPinia();
    store = useDeployFreeze();
    store.projectId = '8';
    store.timezoneData = timezoneDataFixture;
    wrapper = mountFn(DeployFreezeTable, {
      attachTo: document.body,
      pinia,
    });
  };

  const findEmptyFreezePeriods = () => wrapper.findByTestId('empty-freeze-periods');
  const findAddDeployFreezeButton = () => wrapper.findByTestId('add-deploy-freeze');
  const findEditDeployFreezeButton = () => wrapper.findByTestId('edit-deploy-freeze');
  const findDeployFreezeTable = () => wrapper.findByTestId('deploy-freeze-table');
  const findDeleteDeployFreezeButton = () => wrapper.findByTestId('delete-deploy-freeze');
  const findDeleteDeployFreezeModal = () => wrapper.findComponent(GlModal);
  const findCount = () => wrapper.findByTestId('crud-count');

  describe('When mounting', () => {
    beforeEach(() => {
      createComponent(shallowMountExtended);
    });

    it('calls fetchFreezePeriods when mounted', () => {
      expect(store.fetchFreezePeriods).toHaveBeenCalledTimes(1);
    });
  });

  describe('Renders correct data', () => {
    describe('without empty data', () => {
      beforeEach(() => {
        createComponent(shallowMountExtended);
      });

      it('displays empty', () => {
        expect(findEmptyFreezePeriods().exists()).toBe(true);
        expect(wrapper.findComponent(GlSprintf).attributes('message')).toBe(
          'No deploy freezes exist for this project. To add one, select %{strongStart}Add deploy freeze%{strongEnd} above.',
        );
      });
    });

    describe('with data', () => {
      beforeEach(async () => {
        createComponent();
        store.freezePeriods = freezePeriodsFixture
          .map((period) => convertObjectPropsToCamelCase(period))
          .map((f) => ({
            ...f,
            cronTimezone: { formattedTimezone: f.cronTimezone, identifier: f.cronTimezone },
          }));
        await nextTick();
      });

      it('displays data', () => {
        const tableRows = findDeployFreezeTable().findAll('tbody tr');
        expect(tableRows).toHaveLength(freezePeriodsFixture.length);
        expect(findEmptyFreezePeriods().exists()).toBe(false);
        expect(findEditDeployFreezeButton().exists()).toBe(true);
      });

      it('displays correct count', () => {
        const tableRows = findDeployFreezeTable().findAll('tbody tr');
        expect(tableRows).toHaveLength(freezePeriodsFixture.length);
        expect(findCount().text()).toBe('3');
      });

      it('allows user to edit deploy freeze', async () => {
        findEditDeployFreezeButton().trigger('click');
        await nextTick();

        expect(store.setFreezePeriod).toHaveBeenCalledWith(store.freezePeriods[0]);
      });

      it('displays delete deploy freeze button', () => {
        expect(findDeleteDeployFreezeButton().exists()).toBe(true);
      });

      it('confirms a user wants to delete a deploy freeze', async () => {
        const [{ freezeStart, freezeEnd, cronTimezone }] = store.freezePeriods;
        await findDeleteDeployFreezeButton().trigger('click');
        const modal = findDeleteDeployFreezeModal();
        expect(modal.text()).toContain(
          `Deploy freeze from ${freezeStart} to ${freezeEnd} in ${cronTimezone.formattedTimezone} will be removed.`,
        );
      });

      it('deletes the freeze period on confirmation', async () => {
        await findDeleteDeployFreezeButton().trigger('click');
        const modal = findDeleteDeployFreezeModal();
        modal.vm.$emit('primary');
        expect(store.deleteFreezePeriod).toHaveBeenCalledWith(store.freezePeriods[0]);
      });
    });
  });

  describe('Table click actions', () => {
    beforeEach(() => {
      createComponent();
    });

    it('displays add deploy freeze button', () => {
      expect(findAddDeployFreezeButton().exists()).toBe(true);
      expect(findAddDeployFreezeButton().text()).toBe('Add deploy freeze');
    });
  });
});
