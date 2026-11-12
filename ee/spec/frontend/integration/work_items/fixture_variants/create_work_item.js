import createWorkItemBase from 'test_fixtures/graphql/work_items/integration/create_work_item.mutation.graphql.json';
import createChildWorkItem from 'test_fixtures/graphql/work_items/integration/create_child_work_item.mutation.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

// The base recording is a stand-alone issue, which is what the create page sends. The
// create form inside the work item tree sends a parent, so it needs the task recording.
export default defineFixtureVariants({
  query: 'createWorkItem',
  variants: {
    BASE: createWorkItemBase,
    CHILD_TASK: createChildWorkItem,
  },
});
