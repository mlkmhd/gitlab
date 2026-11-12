import { nextTick } from 'vue';
import { GlAlert, GlLink, GlTableLite } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import DbPlannerStatisticsSection from '~/admin/database_diagnostics/components/db_planner_statistics_section.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import {
  plannerStatistics,
  plannerStatisticsEmpty,
  plannerStatisticsRelations,
  plannerStatisticsWithoutFindings,
} from '../mock_data';

describe('DbPlannerStatisticsSection component', () => {
  let wrapper;

  const findStatusIcon = () => wrapper.findComponentByTestId('planner-statistics-status-icon');
  const findCountBadge = () => wrapper.findByTestId('planner-statistics-count');
  const findToggle = () => wrapper.findComponentByTestId('planner-statistics-toggle');
  const findCollapse = () => wrapper.findComponentByTestId('planner-statistics-details');
  const findEmpty = () => wrapper.findByTestId('planner-statistics-empty');
  const findTable = () => wrapper.findComponentByTestId('planner-statistics-table');
  const findStatsReset = () => wrapper.findByTestId('planner-statistics-stats-reset');
  const findCapped = () => wrapper.findByTestId('planner-statistics-capped');
  const findMissingBadge = () => wrapper.findComponentByTestId('planner-statistics-status-missing');
  const findStaleBadge = () => wrapper.findComponentByTestId('planner-statistics-status-stale');
  const findOkBadge = () => wrapper.findComponentByTestId('planner-statistics-status-ok');
  const findAllAlerts = () => wrapper.findAllComponents(GlAlert);
  const findDocsLink = () => wrapper.findComponent(GlLink);

  const createComponent = ({ props = {} } = {}) => {
    wrapper = mountExtended(DbPlannerStatisticsSection, {
      propsData: {
        plannerStatistics: plannerStatisticsWithoutFindings,
        ...props,
      },
    });
  };

  const expand = async () => {
    findToggle().vm.$emit('click');
    await nextTick();
  };

  describe('when there are no findings', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders a green status icon and no count badge', () => {
      expect(findStatusIcon().props('variant')).toBe('success');
      expect(findStatusIcon().props('name')).toBe('check-circle-filled');
      expect(findCountBadge().exists()).toBe(false);
    });

    it('keeps the details collapsed until toggled', async () => {
      expect(findCollapse().props('visible')).toBe(false);

      await expand();

      expect(findCollapse().props('visible')).toBe(true);
    });

    it('exposes the expanded state to assistive technology', async () => {
      expect(findToggle().attributes('aria-expanded')).toBe('false');
      expect(findToggle().attributes('aria-controls')).toBe(findCollapse().attributes('id'));

      await expand();

      expect(findToggle().attributes('aria-expanded')).toBe('true');
    });

    it('renders the partitioned table with its size, estimate, analyze age and interval', () => {
      expect(findTable().props('items')).toEqual([
        {
          name: 'public.p_ci_builds',
          kind: 'Partitioned table',
          heapSize: '3.00 GiB',
          estimatedRows: '9,000,000',
          lastAnalyze: '1 day ago',
          interval: '3 days',
          status: null,
        },
      ]);
    });

    it('marks the healthy partitioned table as OK', () => {
      expect(findOkBadge().props('variant')).toBe('success');
      expect(findOkBadge().text()).toBe('OK');
      expect(findMissingBadge().exists()).toBe(false);
      expect(findStaleBadge().exists()).toBe(false);
    });

    it('omits the statistics reset note', () => {
      expect(findStatsReset().exists()).toBe(false);
    });

    it('omits the cap note', () => {
      expect(findCapped().exists()).toBe(false);
    });

    it('links to the documented planner statistics findings', () => {
      expect(findDocsLink().attributes('href')).toBe(
        '/help/administration/postgresql/vacuum#planner-statistics-findings',
      );
    });
  });

  describe('when there are findings', () => {
    beforeEach(() => {
      createComponent({ props: { plannerStatistics } });
    });

    it('reflects the worst severity in the status icon and shows the count', () => {
      expect(findStatusIcon().props('variant')).toBe('danger');
      expect(findStatusIcon().props('name')).toBe('error');
      expect(findCountBadge().text()).toBe('2');
    });

    it('renders one alert per finding with the mapped variant', () => {
      const alerts = findAllAlerts().wrappers;

      expect(alerts).toHaveLength(2);
      expect(alerts[0].props('variant')).toBe('danger');
      expect(alerts[0].text()).toBe(
        '1 large table has no planner statistics, so PostgreSQL can choose bad query plans for it.',
      );
      expect(alerts[1].props('variant')).toBe('warning');
      expect(alerts[1].text()).toBe(
        '1 partitioned table was last analyzed more than twice its expected interval ago.',
      );
    });

    it('lists the relations in the order supplied, problems first', () => {
      expect(
        findTable()
          .props('items')
          .map((item) => item.name),
      ).toEqual(['public.ci_builds', 'public.audit_events', 'public.p_ci_builds']);
    });

    it('renders a never-analyzed table with no estimate, analyze time or interval', () => {
      expect(findTable().props('items')[0]).toMatchObject({
        kind: 'Table',
        heapSize: '2.00 GiB',
        estimatedRows: 'Not available',
        lastAnalyze: 'Never',
        interval: 'Not applicable',
        status: 'missing',
      });
    });

    it('renders a stale partitioned table with its analyze age and interval', () => {
      expect(findTable().props('items')[1]).toMatchObject({
        kind: 'Partitioned table',
        heapSize: '512.00 MiB',
        estimatedRows: '1,200,000',
        lastAnalyze: '15 days ago',
        interval: '7 days',
        status: 'stale',
      });
    });

    it('marks every row with its status badge', () => {
      expect(findMissingBadge().props('variant')).toBe('danger');
      expect(findMissingBadge().text()).toBe('Missing');
      expect(findStaleBadge().props('variant')).toBe('warning');
      expect(findStaleBadge().text()).toBe('Stale');
      expect(findOkBadge().text()).toBe('OK');
    });

    it('omits the statistics reset note while no analyze time is missing', () => {
      expect(findStatsReset().exists()).toBe(false);
    });
  });

  describe('when an analyzed table has no analyze time', () => {
    beforeEach(() => {
      createComponent({
        props: {
          plannerStatistics: {
            ...plannerStatisticsWithoutFindings,
            stats_reset: '2026-09-01T00:00:00.000Z',
            relations: [
              { ...plannerStatisticsRelations[2], last_analyze: null, analyze_age_seconds: null },
            ],
          },
        },
      });
    });

    it('renders it as not recorded rather than never', () => {
      expect(findTable().props('items')[0].lastAnalyze).toBe('Not recorded');
    });

    it('explains the statistics reset with its time', () => {
      expect(findStatsReset().findComponent(TimeAgoTooltip).props('time')).toBe(
        '2026-09-01T00:00:00.000Z',
      );
    });
  });

  describe('when the check cut the list', () => {
    beforeEach(() => {
      createComponent({
        props: { plannerStatistics: { ...plannerStatistics, relations_capped: true } },
      });
    });

    it('says so under the table with the number of rows shown', () => {
      expect(findCapped().text()).toBe(
        'Only the first 3 relations are listed. The findings above count every table.',
      );
    });
  });

  describe('when nothing reaches the size floor', () => {
    beforeEach(() => {
      createComponent({ props: { plannerStatistics: plannerStatisticsEmpty } });
    });

    it('renders an empty message instead of the table and the toggle', () => {
      expect(findEmpty().exists()).toBe(true);
      expect(findToggle().exists()).toBe(false);
      expect(wrapper.findComponent(GlTableLite).exists()).toBe(false);
    });
  });
});
