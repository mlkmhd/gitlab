import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import PreUpgradeChecks from '~/admin/database_diagnostics/components/pre_upgrade_checks.vue';
import LooseForeignKeysBacklogCheckerApp from '~/admin/database_diagnostics/components/loose_foreign_keys_backlog_checker_app.vue';
import SchemaCheckerApp from '~/admin/database_diagnostics/components/schema_checker_app.vue';
import SearchPathApp from '~/admin/database_diagnostics/components/search_path_app.vue';

describe('PreUpgradeChecks component', () => {
  let wrapper;

  const createComponent = () => {
    wrapper = shallowMountExtended(PreUpgradeChecks);
  };

  const findSearchPath = () => wrapper.findComponent(SearchPathApp);
  const findSchemaChecker = () => wrapper.findComponent(SchemaCheckerApp);
  const findLfkBacklogChecker = () => wrapper.findComponent(LooseForeignKeysBacklogCheckerApp);

  beforeEach(() => {
    createComponent();
  });

  it('renders all pre-upgrade check components', () => {
    expect(findSearchPath().exists()).toBe(true);
    expect(findSchemaChecker().exists()).toBe(true);
    expect(findLfkBacklogChecker().exists()).toBe(true);
  });

  it('renders the checks in order: search path, schema, then LFK backlog', () => {
    const allElements = wrapper.findAll('*').wrappers.map((element) => element.element);
    const positions = [SearchPathApp, SchemaCheckerApp, LooseForeignKeysBacklogCheckerApp].map(
      (component) => allElements.indexOf(wrapper.findComponent(component).element),
    );

    expect(positions).toEqual([...positions].sort((a, b) => a - b));
  });
});
