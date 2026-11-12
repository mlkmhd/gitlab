import { defineStore } from 'pinia';
import {
  CHANGED_STATUS_CHECKS,
  REPOSITORY_SETTINGS_LABEL,
} from 'ee_else_ce/projects/settings/branch_rules/tracking/constants';
import axios from '~/lib/utils/axios_utils';
import {
  convertObjectPropsToCamelCase,
  convertObjectPropsToSnakeCase,
} from '~/lib/utils/common_utils';
import { InternalEvents } from '~/tracking';

export const useStatusChecks = defineStore('statusChecks', {
  state() {
    return {
      settings: { projectId: null, statusChecksPath: null },
      statusChecks: [],
    };
  },
  actions: {
    setSettings(settings) {
      this.settings = settings;
    },
    async fetchStatusChecks() {
      const { data } = await axios.get(this.settings.statusChecksPath);
      this.statusChecks = convertObjectPropsToCamelCase(data, { deep: true });
    },
    async putStatusCheck(statusCheck) {
      const data = convertObjectPropsToSnakeCase(statusCheck, { deep: true });

      await axios.put(`${this.settings.statusChecksPath}/${statusCheck.id}`, data);
      InternalEvents.trackEvent(CHANGED_STATUS_CHECKS, {
        label: REPOSITORY_SETTINGS_LABEL,
      });
      this.fetchStatusChecks();
    },
    async postStatusCheck(statusCheck) {
      const data = convertObjectPropsToSnakeCase(statusCheck, { deep: true });

      await axios.post(this.settings.statusChecksPath, data);
      InternalEvents.trackEvent(CHANGED_STATUS_CHECKS, {
        label: REPOSITORY_SETTINGS_LABEL,
      });
      this.fetchStatusChecks();
    },
    async deleteStatusCheck(id) {
      await axios.delete(`${this.settings.statusChecksPath}/${id}`);
      InternalEvents.trackEvent(CHANGED_STATUS_CHECKS, {
        label: REPOSITORY_SETTINGS_LABEL,
      });
      this.fetchStatusChecks();
    },
  },
});
