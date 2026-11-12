import base from 'test_fixtures/graphql/repository/integration/get_workspaces_namespace_cluster_agents.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureItemsCount } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'getWorkspacesNamespaceClusterAgents',
  variants: {
    BASE: base,
    NO_AGENTS: setFixtureItemsCount({
      fixture: base,
      lookupKey: 'workspacesClusterAgents',
      itemCount: 0,
    }),
  },
});
