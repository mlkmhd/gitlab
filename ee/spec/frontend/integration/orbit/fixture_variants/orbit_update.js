import base from 'test_fixtures/graphql/orbit/integration/orbit_update.mutation.graphql.json';
import withError from 'test_fixtures/graphql/orbit/integration/orbit_update_error.mutation.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export const [ORBIT_UPDATE_ERROR] = withError.data.orbitUpdate.errors;

export default defineFixtureVariants({
  query: 'orbitUpdate',
  variants: {
    BASE: base,
    WITH_ERROR: withError,
  },
});
