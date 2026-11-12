import workItemTreeQueryFeaturesBase from 'test_fixtures/graphql/work_items/integration/work_item_tree_query_features.query.graphql.json';
import workItemTreeQueryFeaturesWithChildren from 'test_fixtures/graphql/work_items/integration/work_item_tree_query_with_children_features.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { withoutEditPermissions } from './edit_permissions';

export default defineFixtureVariants({
  query: 'workItemTreeQueryFeatures',
  variants: {
    BASE: workItemTreeQueryFeaturesBase,
    READ_ONLY: withoutEditPermissions(workItemTreeQueryFeaturesBase),
    WITH_CHILDREN: workItemTreeQueryFeaturesWithChildren,
  },
});
