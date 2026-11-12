import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SearchPathApp from '~/admin/database_diagnostics/components/search_path_app.vue';
import DbSearchPathCard from '~/admin/database_diagnostics/components/db_search_path_card.vue';
import { searchPathInformationResults } from '../mock_data';

describe('SearchPathApp component', () => {
  let wrapper;

  const findTitle = () => wrapper.findByTestId('title');
  const findCards = () => wrapper.findAllComponents(DbSearchPathCard);

  const createComponent = ({ searchPathInformation = searchPathInformationResults } = {}) => {
    wrapper = shallowMountExtended(SearchPathApp, {
      provide: { searchPathInformation },
    });
  };

  beforeEach(() => {
    createComponent();
  });

  it('renders the section title', () => {
    expect(findTitle().text()).toBe('Search path check');
  });

  it('renders one card per database', () => {
    expect(findCards()).toHaveLength(1);
  });

  it('passes the database name and payload to each card', () => {
    expect(findCards().at(0).props()).toMatchObject({
      dbName: 'main',
      payload: searchPathInformationResults.databases.main,
    });
  });
});
