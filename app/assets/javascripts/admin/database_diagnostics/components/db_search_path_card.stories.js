import {
  databaseInformationWithDatabaseError,
  searchPathInformationResults,
  searchPathInformationWithFindings,
} from 'jest/admin/database_diagnostics/mock_data';
import DbSearchPathCard from './db_search_path_card.vue';

export default {
  title: 'admin/database_diagnostics/components/db_search_path_card',
  component: DbSearchPathCard,
  parameters: {
    docs: {
      description: {
        component:
          'One card per database, holding the search path and schemas sections. The search path section starts collapsed.',
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
  components: { DbSearchPathCard },
  template: '<db-search-path-card v-bind="$props" />',
});

export const Default = Template.bind({});
Default.args = { dbName: 'main', payload: searchPathInformationResults.databases.main };

// Findings render as alerts above the current user and search path line.
export const WithFindings = Template.bind({});
WithFindings.args = {
  dbName: 'main',
  payload: searchPathInformationWithFindings.databases.main,
};

// A database that could not be read at all: one warning alert, and every
// section suppressed.
export const DatabaseError = Template.bind({});
DatabaseError.args = {
  dbName: 'main',
  payload: databaseInformationWithDatabaseError.databases.main,
};
