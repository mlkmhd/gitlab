import {
  databaseInformationResults,
  databaseInformationWithDatabaseError,
} from 'jest/admin/database_diagnostics/mock_data';
import DbInformationCard from './db_information_card.vue';

export default {
  title: 'admin/database_diagnostics/components/db_information_card',
  component: DbInformationCard,
  parameters: {
    docs: {
      description: {
        component:
          'One card per database, holding the timeouts and planner statistics sections. Each section starts collapsed.',
      },
    },
  },
  argTypes: {
    dbName: { control: 'text' },
    payload: { control: false },
  },
};

const Template = (args, { argTypes }) => ({
  props: Object.keys(argTypes),
  components: { DbInformationCard },
  template: '<db-information-card v-bind="$props" />',
});

export const Default = Template.bind({});
Default.args = { dbName: 'main', payload: databaseInformationResults.databases.main };

// A database that could not be read at all: one warning alert, and every
// section suppressed.
export const DatabaseError = Template.bind({});
DatabaseError.args = {
  dbName: 'main',
  payload: databaseInformationWithDatabaseError.databases.main,
};
