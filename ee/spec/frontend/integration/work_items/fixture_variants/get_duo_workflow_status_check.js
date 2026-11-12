import getDuoWorkflowStatusCheckBase from 'test_fixtures/graphql/work_items/integration/get_duo_workflow_status_check.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData } from 'ee_jest/integration/core/fixture_utils';

export default defineFixtureVariants({
  query: 'getDuoWorkflowStatusCheck',
  variants: {
    BASE: getDuoWorkflowStatusCheckBase,
    FLOW_ALLOWED: setFixtureData(
      getDuoWorkflowStatusCheckBase,
      'createDuoWorkflowForCiAllowed',
      true,
    ),
  },
});
