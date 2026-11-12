import workItemMetadataBase from 'test_fixtures/graphql/work_items/integration/work_item_metadata.query.graphql.json';
import workItemMetadataGroup from 'test_fixtures/graphql/work_items/integration/work_item_metadata_group.query.graphql.json';
import workItemMetadataAnonymous from 'test_fixtures/graphql/work_items/integration/work_item_metadata_anonymous.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'workItemMetadataEE',
  variants: {
    BASE: workItemMetadataBase,
    // The list reads isGroup from the metadata namespace, so group mounts need group metadata.
    GROUP: workItemMetadataGroup,
    ANONYMOUS: workItemMetadataAnonymous,
  },
});
