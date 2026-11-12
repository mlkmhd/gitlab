import { activeSessionHistoryTimelines } from 'jest/admin/database_diagnostics/mock_data';
import ActiveSessionHistoryChart from './active_session_history_chart.vue';

// As in the app, a minute without samples shows no load.
const series = Object.entries(activeSessionHistoryTimelines).map(([name, timeline]) => ({
  name,
  data: timeline.map(({ bucket_start: bucketStart, avg_aas: avg }) => [bucketStart, avg ?? 0]),
}));

const hours = (loads) => loads.map((load, hour) => [`2026-10-15T0${7 + hour}:00:00Z`, load]);

export default {
  title: 'admin/database_diagnostics/components/active_session_history_chart',
  component: ActiveSessionHistoryChart,
  argTypes: {
    series: { control: false },
  },
};

const Template = (args, { argTypes }) => ({
  props: Object.keys(argTypes),
  components: { ActiveSessionHistoryChart },
  template: '<active-session-history-chart v-bind="$props" />',
});

// Lock is busiest from 09:10 to 09:14, and no minute is sampled at 09:30.
export const Default = Template.bind({});
Default.args = { series };

// The current hour has no summary yet, so it stays empty.
export const Hourly = Template.bind({});
Hourly.args = {
  series: [
    { name: 'Lock', data: hours([2, 2, null]) },
    { name: 'CPU*', data: hours([1, 0, null]) },
  ],
  hourly: true,
};
