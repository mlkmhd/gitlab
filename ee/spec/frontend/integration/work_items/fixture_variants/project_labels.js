import projectLabelsBase from 'test_fixtures/graphql/work_items/integration/project_labels.query.graphql.json';
import projectLabelsWithGroupAndMarkup from 'test_fixtures/graphql/work_items/integration/project_labels_with_group_and_markup.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'projectLabels',
  variants: {
    BASE: projectLabelsBase,
    // Adds a group label and a label whose title is markup to the seeded project labels.
    WITH_GROUP_AND_MARKUP: projectLabelsWithGroupAndMarkup,
  },
});
