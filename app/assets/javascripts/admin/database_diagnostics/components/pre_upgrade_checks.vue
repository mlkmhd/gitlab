<script>
import LooseForeignKeysBacklogCheckerApp from './loose_foreign_keys_backlog_checker_app.vue';
import SchemaCheckerApp from './schema_checker_app.vue';
import SearchPathApp from './search_path_app.vue';

export default {
  name: 'PreUpgradeChecks',
  components: {
    LooseForeignKeysBacklogCheckerApp,
    SchemaCheckerApp,
    SearchPathApp,
  },
};
</script>

<template>
  <section>
    <section class="gl-mb-8">
      <search-path-app />
    </section>

    <section class="gl-mb-8">
      <schema-checker-app />
    </section>

    <section class="gl-mb-8">
      <loose-foreign-keys-backlog-checker-app />
    </section>
  </section>
</template>
