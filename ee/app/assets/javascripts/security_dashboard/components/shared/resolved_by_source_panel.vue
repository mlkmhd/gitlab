<script>
import ExtendedDashboardPanel from '~/vue_shared/components/customizable_dashboard/extended_dashboard_panel.vue';
import { readFromUrl, writeToUrl } from 'ee/security_dashboard/utils/panel_state_url_sync';
import OverTimePeriodSelector from './over_time_period_selector.vue';

const PANEL_ID = 'vulnerabilitiesResolvedBySource';
const TIME_PERIOD_DEFAULT = 30;

export default {
  name: 'ResolvedBySourcePanel',
  components: {
    ExtendedDashboardPanel,
    OverTimePeriodSelector,
  },
  data() {
    return {
      selectedTimePeriod: readFromUrl({
        panelId: PANEL_ID,
        paramName: 'timePeriod',
        defaultValue: TIME_PERIOD_DEFAULT,
      }),
    };
  },
  watch: {
    selectedTimePeriod(value) {
      writeToUrl({
        panelId: PANEL_ID,
        paramName: 'timePeriod',
        value,
        defaultValue: TIME_PERIOD_DEFAULT,
      });
    },
  },
};
</script>

<template>
  <extended-dashboard-panel :title="s__('SecurityReports|Resolution breakdown')">
    <template #filters>
      <over-time-period-selector v-model="selectedTimePeriod" />
    </template>
  </extended-dashboard-panel>
</template>
