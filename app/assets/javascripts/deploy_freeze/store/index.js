import { defineStore } from 'pinia';
import Api from '~/api';
import { createAlert } from '~/alert';
import { convertObjectPropsToCamelCase } from '~/lib/utils/common_utils';
import { formatTimezone } from '~/lib/utils/datetime_utility';
import { logError } from '~/lib/logger';
import { __ } from '~/locale';

const formatTimezoneName = (freezePeriod, timezoneList) => {
  const tz = timezoneList.find((timezone) => timezone.identifier === freezePeriod.cron_timezone);
  return convertObjectPropsToCamelCase({
    ...freezePeriod,
    cron_timezone: {
      formattedTimezone: tz && formatTimezone(tz),
      identifier: freezePeriod.cron_timezone,
    },
  });
};

const receiveFreezePeriod = (store, request) =>
  request()
    .then(() => {
      store.resetModal();
      store.fetchFreezePeriods();
    })
    .catch(() => {
      createAlert({
        message: __('Error: Unable to create deploy freeze'),
      });
    });

export const useDeployFreeze = defineStore('deployFreeze', {
  state() {
    return {
      projectId: undefined,
      freezePeriods: [],
      timezoneData: [],
      selectedTimezone: '',
      selectedTimezoneIdentifier: '',
      freezeStartCron: '',
      freezeEndCron: '',
      selectedId: '',
    };
  },
  actions: {
    setInitialState({
      projectId,
      freezePeriods = [],
      timezoneData = [],
      selectedTimezone = '',
      selectedTimezoneIdentifier = '',
      freezeStartCron = '',
      freezeEndCron = '',
      selectedId = '',
    } = {}) {
      this.projectId = projectId;
      this.freezePeriods = freezePeriods;
      this.timezoneData = timezoneData;
      this.selectedTimezone = selectedTimezone;
      this.selectedTimezoneIdentifier = selectedTimezoneIdentifier;
      this.freezeStartCron = freezeStartCron;
      this.freezeEndCron = freezeEndCron;
      this.selectedId = selectedId;
    },
    addFreezePeriod() {
      return receiveFreezePeriod(this, () =>
        Api.createFreezePeriod(this.projectId, {
          freeze_start: this.freezeStartCron,
          freeze_end: this.freezeEndCron,
          cron_timezone: this.selectedTimezoneIdentifier,
        }),
      );
    },
    updateFreezePeriod() {
      return receiveFreezePeriod(this, () =>
        Api.updateFreezePeriod(this.projectId, {
          id: this.selectedId,
          freeze_start: this.freezeStartCron,
          freeze_end: this.freezeEndCron,
          cron_timezone: this.selectedTimezoneIdentifier,
        }),
      );
    },
    deleteFreezePeriod({ id }) {
      const freezePeriod = this.freezePeriods.find((f) => f.id === id);

      if (freezePeriod) {
        freezePeriod.isDeleting = true;
      }

      return Api.deleteFreezePeriod(this.projectId, id)
        .then(() => {
          this.freezePeriods = this.freezePeriods.filter((f) => f.id !== id);
        })
        .catch((e) => {
          createAlert({
            message: __('Error: Unable to delete deploy freeze'),
          });
          if (freezePeriod) {
            freezePeriod.isDeleting = false;
          }

          logError(`Unable to delete deploy freeze`, e);
        });
    },
    fetchFreezePeriods() {
      return Api.freezePeriods(this.projectId)
        .then(({ data }) => {
          this.freezePeriods = data.map((freezePeriod) =>
            formatTimezoneName(freezePeriod, this.timezoneData),
          );
        })
        .catch(() => {
          createAlert({
            message: __('There was an error fetching the deploy freezes.'),
          });
        });
    },
    setFreezePeriod(freezePeriod) {
      this.selectedId = freezePeriod.id;
      this.setSelectedTimezone(freezePeriod.cronTimezone);
      this.freezeStartCron = freezePeriod.freezeStart;
      this.freezeEndCron = freezePeriod.freezeEnd;
    },
    setSelectedTimezone(timezone) {
      this.selectedTimezone = timezone.formattedTimezone;
      this.selectedTimezoneIdentifier = timezone.identifier;
    },
    resetModal() {
      this.freezeStartCron = '';
      this.freezeEndCron = '';
      this.selectedTimezone = '';
      this.selectedTimezoneIdentifier = '';
      this.selectedId = '';
    },
  },
});
