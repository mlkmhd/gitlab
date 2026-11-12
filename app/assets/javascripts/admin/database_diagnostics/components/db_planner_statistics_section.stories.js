import {
  plannerStatistics,
  plannerStatisticsWithoutFindings,
  plannerStatisticsEmpty,
} from 'jest/admin/database_diagnostics/mock_data';
import DbPlannerStatisticsSection from './db_planner_statistics_section.vue';

export default {
  title: 'admin/database_diagnostics/components/db_planner_statistics_section',
  component: DbPlannerStatisticsSection,
  parameters: {
    docs: {
      description: {
        component:
          'Lists large tables PostgreSQL never analyzed and large partitioned tables with how long ago each was last analyzed. Details start collapsed, so use the Details toggle to reveal the table.',
      },
    },
  },
  argTypes: {
    plannerStatistics: { control: false },
  },
};

const Template = (args, { argTypes }) => ({
  props: Object.keys(argTypes),
  components: { DbPlannerStatisticsSection },
  template: '<db-planner-statistics-section v-bind="$props" />',
});

// A never-analyzed table (error) and a stale partitioned table (warning).
export const Default = Template.bind({});
Default.args = { plannerStatistics };

export const NoFindings = Template.bind({});
NoFindings.args = { plannerStatistics: plannerStatisticsWithoutFindings };

// Nothing reaches the size floor, as on a fresh install.
export const Empty = Template.bind({});
Empty.args = { plannerStatistics: plannerStatisticsEmpty };
