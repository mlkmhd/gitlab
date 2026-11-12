import getConfiguredFlowsBase from 'test_fixtures/graphql/work_items/integration/get_configured_flows.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'getConfiguredFlows',
  variants: {
    BASE: getConfiguredFlowsBase,
    WITH_DEVELOPER_FLOW: setFixtureData(
      getConfiguredFlowsBase,
      { path: 'aiCatalogConfiguredItems.nodes' },
      [{ __typename: 'AiCatalogItemConsumer', id: 'gid://gitlab/Ai::CatalogItemConsumer/1' }],
    ),
  },
});
