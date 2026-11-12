<script>
import { GlAreaChart } from '@gitlab/ui/src/charts';
import { localeDateFormat } from '~/lib/utils/datetime_utility';
import { formatNumber, s__ } from '~/locale';
import { formatActiveSessions } from '../utils';

export default {
  name: 'ActiveSessionHistoryChart',
  components: { GlAreaChart },
  props: {
    // One series per wait event type, in stacking order, as [bucket start, load] pairs.
    series: {
      type: Array,
      required: true,
    },
    // True when pg_ash read hourly summaries, so each point is an hour.
    hourly: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    chartData() {
      // An hour with samples between two without draws no area, so hours show their points.
      return this.series.map(({ name, data }) => ({
        name,
        data,
        stack: 'active-sessions',
        showSymbol: this.hourly,
      }));
    },
    chartOption() {
      return {
        xAxis: { name: '', type: 'time' },
        yAxis: {
          name: s__('DatabaseDiagnostics|Average active sessions'),
          type: 'value',
          // At least one session high, so a nearly idle database does not fill the chart.
          max: ({ max }) => (max < 1 ? 1 : null),
          // The default engineering notation shows 0.01 as 10m, which reads as minutes.
          axisLabel: { formatter: (value) => formatNumber(value) },
        },
        aria: {
          label: {
            description: [
              this.hourly
                ? s__(
                    'DatabaseDiagnostics|Average active sessions per hour, stacked by wait event type.',
                  )
                : s__(
                    'DatabaseDiagnostics|Average active sessions per minute, stacked by wait event type.',
                  ),
              s__(
                'DatabaseDiagnostics|The wait event types table lists the load of each type over the whole time range.',
              ),
            ].join(' '),
          },
        },
      };
    },
  },
  methods: {
    formatActiveSessions,
    formatTooltipTitle(params) {
      const time = params?.seriesData?.at(0)?.value?.at(0);

      return time ? localeDateFormat.asDateTime.format(new Date(time)) : '';
    },
  },
};
</script>

<template>
  <gl-area-chart :data="chartData" :option="chartOption" :include-legend-avg-max="false">
    <template #tooltip-title="{ params }">{{ formatTooltipTitle(params) }}</template>
    <template #tooltip-value="{ value }">{{ formatActiveSessions(value) }}</template>
  </gl-area-chart>
</template>
