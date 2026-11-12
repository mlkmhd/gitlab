import base from 'test_fixtures/graphql/orbit/integration/get_orbit_group_settings.query.graphql.json';
import indexing from 'test_fixtures/graphql/orbit/integration/get_orbit_group_settings_indexing.query.graphql.json';
import ready from 'test_fixtures/graphql/orbit/integration/get_orbit_group_settings_ready.query.graphql.json';
import trialEnded from 'test_fixtures/graphql/orbit/integration/get_orbit_group_settings_trial_ended.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';

export default defineFixtureVariants({
  query: 'getOrbitGroupSettings',
  variants: {
    // Orbit is off and the group's plan lets the Owner turn it on.
    BASE: base,
    INDEXING: indexing,
    READY: ready,
    TRIAL_ENDED: trialEnded,
  },
});
