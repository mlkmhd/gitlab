import { createTestingPinia } from '@pinia/testing';
import Api from '~/api';
import { createAlert } from '~/alert';
import { useDeployFreeze } from '~/deploy_freeze/store';
import * as logger from '~/lib/logger';
import { convertObjectPropsToCamelCase } from '~/lib/utils/common_utils';
import { formatTimezone } from '~/lib/utils/datetime_utility';
import { freezePeriodsFixture } from '../helpers';
import {
  timezoneDataFixture,
  findTzByName,
} from '../../vue_shared/components/timezone_dropdown/helpers';

jest.mock('~/api.js');
jest.mock('~/alert');

describe('deploy freeze store', () => {
  const freezePeriodFixture = freezePeriodsFixture[0];
  let store;

  beforeEach(() => {
    createTestingPinia({ stubActions: false });
    store = useDeployFreeze();
    store.setInitialState({
      projectId: '8',
      timezoneData: timezoneDataFixture,
    });
    Api.freezePeriods.mockResolvedValue({ data: freezePeriodsFixture });
    Api.createFreezePeriod.mockResolvedValue();
    Api.updateFreezePeriod.mockResolvedValue();
    Api.deleteFreezePeriod.mockResolvedValue();
  });

  describe('setInitialState', () => {
    it('has empty defaults', () => {
      store.setInitialState();

      expect(store.$state).toEqual({
        projectId: undefined,
        freezePeriods: [],
        timezoneData: [],
        selectedTimezone: '',
        selectedTimezoneIdentifier: '',
        freezeStartCron: '',
        freezeEndCron: '',
        selectedId: '',
      });
    });

    it('seeds the state from the given values', () => {
      expect(store.projectId).toBe('8');
      expect(store.timezoneData).toEqual(timezoneDataFixture);
    });
  });

  describe('resetModal', () => {
    it('should reset modal state', () => {
      store.freezeStartCron = '5 0 * 8 *';
      store.freezeEndCron = '5 0 * 8 *';
      store.selectedTimezone = 'UTC';
      store.selectedTimezoneIdentifier = 'Etc/UTC';
      store.selectedId = 5;

      store.resetModal();

      expect(store.freezeStartCron).toBe('');
      expect(store.freezeEndCron).toBe('');
      expect(store.selectedTimezone).toBe('');
      expect(store.selectedTimezoneIdentifier).toBe('');
      expect(store.selectedId).toBe('');
    });
  });

  describe('setFreezePeriod', () => {
    it('sets the selected freeze period', () => {
      const cronTimezone = { formattedTimezone: '[UTC 0] UTC', identifier: 'Etc/UTC' };

      store.setFreezePeriod({
        id: 3,
        cronTimezone,
        freezeStart: 'start',
        freezeEnd: 'end',
      });

      expect(store.selectedId).toBe(3);
      expect(store.selectedTimezone).toBe(cronTimezone.formattedTimezone);
      expect(store.selectedTimezoneIdentifier).toBe(cronTimezone.identifier);
      expect(store.freezeStartCron).toBe('start');
      expect(store.freezeEndCron).toBe('end');
    });
  });

  describe('setSelectedTimezone', () => {
    it('should set the cron timezone', () => {
      const selectedTz = findTzByName('Pacific Time (US & Canada)');
      const timezone = {
        formattedTimezone: formatTimezone(selectedTz),
        identifier: selectedTz.identifier,
      };

      store.setSelectedTimezone(timezone);

      expect(store.selectedTimezone).toEqual(timezone.formattedTimezone);
      expect(store.selectedTimezoneIdentifier).toEqual(timezone.identifier);
    });
  });

  describe('addFreezePeriod', () => {
    beforeEach(() => {
      store.freezeStartCron = 'start';
      store.freezeEndCron = 'end';
      store.selectedTimezoneIdentifier = 'Etc/UTC';
    });

    it('calls the correct actions on adding a freeze period', async () => {
      await store.addFreezePeriod();

      expect(store.resetModal).toHaveBeenCalledTimes(1);
      expect(store.fetchFreezePeriods).toHaveBeenCalledTimes(1);
      expect(Api.createFreezePeriod).toHaveBeenCalledWith('8', {
        freeze_start: 'start',
        freeze_end: 'end',
        cron_timezone: 'Etc/UTC',
      });
    });

    it('should show alert on add failure', async () => {
      const error = new Error();
      Api.createFreezePeriod.mockRejectedValue(error);

      await store.addFreezePeriod();

      expect(store.resetModal).not.toHaveBeenCalled();
      expect(store.fetchFreezePeriods).not.toHaveBeenCalled();
      expect(createAlert).toHaveBeenCalledWith({
        message: 'Error: Unable to create deploy freeze',
      });
    });
  });

  describe('updateFreezePeriod', () => {
    beforeEach(() => {
      store.selectedId = 5;
      store.freezeStartCron = 'start';
      store.freezeEndCron = 'end';
      store.selectedTimezoneIdentifier = 'Etc/UTC';
    });

    it('calls the correct actions on updating a freeze period', async () => {
      await store.updateFreezePeriod();

      expect(store.resetModal).toHaveBeenCalledTimes(1);
      expect(store.fetchFreezePeriods).toHaveBeenCalledTimes(1);
      expect(Api.updateFreezePeriod).toHaveBeenCalledWith('8', {
        id: 5,
        freeze_start: 'start',
        freeze_end: 'end',
        cron_timezone: 'Etc/UTC',
      });
    });

    it('should show alert on update failure', async () => {
      const error = new Error();
      Api.updateFreezePeriod.mockRejectedValue(error);

      await store.updateFreezePeriod();

      expect(store.resetModal).not.toHaveBeenCalled();
      expect(store.fetchFreezePeriods).not.toHaveBeenCalled();
      expect(createAlert).toHaveBeenCalledWith({
        message: 'Error: Unable to create deploy freeze',
      });
    });
  });

  describe('fetchFreezePeriods', () => {
    it('sets freeze periods and formats timezones from identifiers to names', async () => {
      const timezoneNames = {
        'Europe/Berlin': '[UTC+2] Berlin',
        'Etc/UTC': '[UTC 0] UTC',
        'America/New_York': '[UTC-4] Eastern Time (US & Canada)',
      };

      await store.fetchFreezePeriods();

      const expectedFreezePeriods = freezePeriodsFixture.map((freezePeriod) => ({
        ...convertObjectPropsToCamelCase(freezePeriod),
        cronTimezone: {
          formattedTimezone: timezoneNames[freezePeriod.cron_timezone],
          identifier: freezePeriod.cron_timezone,
        },
      }));

      expect(Api.freezePeriods).toHaveBeenCalledWith('8');
      expect(store.freezePeriods).toMatchObject(expectedFreezePeriods);
    });

    it('should show alert on fetch failure', async () => {
      Api.freezePeriods.mockRejectedValue();

      await store.fetchFreezePeriods();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'There was an error fetching the deploy freezes.',
      });
    });
  });

  describe('deleteFreezePeriod', () => {
    beforeEach(() => {
      store.freezePeriods = [{ id: freezePeriodFixture.id }, { id: 'other' }];
    });

    it('marks the freeze period as deleting while the request is pending', () => {
      store.deleteFreezePeriod(freezePeriodFixture);

      expect(store.freezePeriods[0].isDeleting).toBe(true);
      expect(Api.deleteFreezePeriod).toHaveBeenCalledWith('8', freezePeriodFixture.id);
    });

    it('removes the freeze period on success', async () => {
      await store.deleteFreezePeriod(freezePeriodFixture);

      expect(store.freezePeriods).toEqual([{ id: 'other' }]);
    });

    it('does nothing to the list when the freeze period is unknown', async () => {
      await store.deleteFreezePeriod({ id: 'unknown' });

      expect(store.freezePeriods).toEqual([{ id: freezePeriodFixture.id }, { id: 'other' }]);
    });

    it('should show alert and reset the deleting flag on delete failure', async () => {
      jest.spyOn(logger, 'logError').mockImplementation();
      const error = new Error();
      Api.deleteFreezePeriod.mockRejectedValue(error);

      await store.deleteFreezePeriod(freezePeriodFixture);

      expect(store.freezePeriods).toHaveLength(2);
      expect(store.freezePeriods[0].isDeleting).toBe(false);
      expect(createAlert).toHaveBeenCalledWith({
        message: 'Error: Unable to delete deploy freeze',
      });
      expect(logger.logError).toHaveBeenCalledWith('Unable to delete deploy freeze', error);
    });
  });
});
