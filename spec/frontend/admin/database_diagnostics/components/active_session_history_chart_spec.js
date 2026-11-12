import { GlAreaChart } from '@gitlab/ui/src/charts';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ActiveSessionHistoryChart from '~/admin/database_diagnostics/components/active_session_history_chart.vue';

describe('ActiveSessionHistoryChart component', () => {
  let wrapper;

  const series = [
    {
      name: 'Lock',
      data: [
        ['2026-10-15T09:10:00Z', 4],
        ['2026-10-15T09:11:00Z', 4],
      ],
    },
    {
      name: 'CPU*',
      data: [
        ['2026-10-15T09:10:00Z', 0.5],
        ['2026-10-15T09:11:00Z', 0.5],
      ],
    },
  ];

  const createComponent = ({ props = {}, stubs = {} } = {}) => {
    wrapper = shallowMountExtended(ActiveSessionHistoryChart, {
      propsData: { series, ...props },
      stubs,
    });
  };

  const findAreaChart = () => wrapper.findComponent(GlAreaChart);

  describe('rendering', () => {
    beforeEach(() => {
      createComponent();
    });

    it('stacks the wait event types, with a plain legend', () => {
      expect(findAreaChart().props('data')).toEqual(
        series.map(({ name, data }) => ({
          name,
          data,
          stack: 'active-sessions',
          showSymbol: false,
        })),
      );
      expect(findAreaChart().props('includeLegendAvgMax')).toBe(false);
    });

    it('labels loads under one session as plain numbers, not as 10m', () => {
      expect(findAreaChart().props('option').yAxis.axisLabel.formatter(0.01)).toBe('0.01');
    });

    it('scales to at least one session, so a nearly idle database stays small', () => {
      const { max } = findAreaChart().props('option').yAxis;

      expect(max({ max: 0.03 })).toBe(1);
      expect(max({ max: 26 })).toBeNull();
    });

    it('describes the chart for screen readers', () => {
      expect(findAreaChart().props('option').aria.label.description).toBe(
        'Average active sessions per minute, stacked by wait event type. The wait event types table lists the load of each type over the whole time range.',
      );
    });
  });

  describe('when the chart shows hours', () => {
    beforeEach(() => {
      createComponent({ props: { hourly: true } });
    });

    it('marks the points', () => {
      expect(
        findAreaChart()
          .props('data')
          .map(({ showSymbol }) => showSymbol),
      ).toEqual([true, true]);
    });

    it('describes the load per hour for screen readers', () => {
      expect(findAreaChart().props('option').aria.label.description).toBe(
        'Average active sessions per hour, stacked by wait event type. The wait event types table lists the load of each type over the whole time range.',
      );
    });
  });

  describe('tooltip', () => {
    beforeEach(() => {
      createComponent({
        stubs: {
          GlAreaChart: {
            template: `<div>
              <slot name="tooltip-title" :params="{ seriesData: [{ value: ['2026-10-15T09:10:00Z', 4] }] }" />
              <slot name="tooltip-value" :value="0.5" />
              <slot name="tooltip-value" :value="null" />
            </div>`,
          },
        },
      });
    });

    it('formats the time and loads', () => {
      expect(wrapper.text().replace(/\s+/g, ' ')).toBe('Oct 15, 2026, 9:10 AM 0.50 Not available');
    });
  });
});
