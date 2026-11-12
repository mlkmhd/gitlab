import projectMilestonesBase from 'test_fixtures/graphql/work_items/integration/project_milestones.query.graphql.json';
import projectMilestonesWithExpired from 'test_fixtures/graphql/work_items/integration/project_milestones_with_expired.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'projectMilestones',
  variants: {
    BASE: projectMilestonesBase,
    // Adds an expired and an undated milestone, in the order the server sorts them.
    WITH_EXPIRED: projectMilestonesWithExpired,
  },
});
