<script>
import DbSearchPathCard from './db_search_path_card.vue';

export default {
  name: 'SearchPathApp',
  components: { DbSearchPathCard },
  inject: ['searchPathInformation'],
  computed: {
    databases() {
      return Object.entries(this.searchPathInformation.databases).map(([name, payload]) => ({
        name,
        payload,
      }));
    },
  },
};
</script>

<template>
  <section>
    <h2 data-testid="title">{{ s__('DatabaseDiagnostics|Search path check') }}</h2>
    <p>
      {{
        s__(
          'DatabaseDiagnostics|Detect GitLab objects that the search path of each database connection cannot resolve as expected.',
        )
      }}
    </p>

    <db-search-path-card
      v-for="database in databases"
      :key="database.name"
      :db-name="database.name"
      :payload="database.payload"
    />
  </section>
</template>
