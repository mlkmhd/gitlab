import { GlAlert } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import DbInformationCard from '~/admin/database_diagnostics/components/db_information_card.vue';
import DbPlannerStatisticsSection from '~/admin/database_diagnostics/components/db_planner_statistics_section.vue';
import DbTimeoutsSection from '~/admin/database_diagnostics/components/db_timeouts_section.vue';
import { databaseInformationResults, databaseInformationWithDatabaseError } from '../mock_data';

describe('DbInformationCard component', () => {
  let wrapper;

  const findAlert = () => wrapper.findComponent(GlAlert);
  const findTimeoutsSection = () => wrapper.findComponent(DbTimeoutsSection);
  const findPlannerStatisticsSection = () => wrapper.findComponent(DbPlannerStatisticsSection);

  const createComponent = ({ props = {} } = {}) => {
    wrapper = mountExtended(DbInformationCard, {
      propsData: {
        dbName: 'main',
        payload: databaseInformationResults.databases.main,
        ...props,
      },
    });
  };

  it('renders the database name in the header', () => {
    createComponent();

    expect(wrapper.findByTestId('database-main').text()).toContain('Database: main');
  });

  it('renders the timeouts section with the payload timeouts', () => {
    createComponent();

    expect(findTimeoutsSection().props('timeouts')).toEqual(
      databaseInformationResults.databases.main.timeouts,
    );
  });

  it('renders the planner statistics section with the payload planner statistics', () => {
    createComponent();

    expect(findPlannerStatisticsSection().props('plannerStatistics')).toEqual(
      databaseInformationResults.databases.main.planner_statistics,
    );
  });

  it('does not render the check sections when the payload has no check results', () => {
    createComponent({ props: { payload: {} } });

    expect(findTimeoutsSection().exists()).toBe(false);
    expect(findPlannerStatisticsSection().exists()).toBe(false);
  });

  describe('when the payload has an error', () => {
    beforeEach(() => {
      createComponent({ props: { payload: databaseInformationWithDatabaseError.databases.main } });
    });

    it('renders a warning alert with the error message and no check sections', () => {
      expect(findAlert().props('variant')).toBe('warning');
      expect(findAlert().text()).toBe('connection refused');
      expect(findTimeoutsSection().exists()).toBe(false);
      expect(findPlannerStatisticsSection().exists()).toBe(false);
    });
  });
});
