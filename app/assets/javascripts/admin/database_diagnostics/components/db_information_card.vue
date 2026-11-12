<script>
import { GlAlert, GlCard, GlSprintf } from '@gitlab/ui';
import { s__ } from '~/locale';
import DbPlannerStatisticsSection from './db_planner_statistics_section.vue';
import DbTimeoutsSection from './db_timeouts_section.vue';

export default {
  name: 'DbInformationCard',
  components: {
    GlAlert,
    GlCard,
    GlSprintf,
    DbPlannerStatisticsSection,
    DbTimeoutsSection,
  },
  props: {
    dbName: {
      type: String,
      required: true,
    },
    payload: {
      type: Object,
      required: true,
    },
  },
  i18n: {
    header: s__('DatabaseDiagnostics|Database: %{name}'),
  },
};
</script>

<template>
  <div class="gl-mb-6" :data-testid="`database-${dbName}`">
    <gl-card class="gl-w-full">
      <template #header>
        <h3 class="gl-heading-5 !gl-mb-0">
          <gl-sprintf :message="$options.i18n.header">
            <template #name>{{ dbName }}</template>
          </gl-sprintf>
        </h3>
      </template>

      <gl-alert v-if="payload.error" variant="warning" :dismissible="false">
        {{ payload.error }}
      </gl-alert>

      <template v-else>
        <db-timeouts-section v-if="payload.timeouts" :timeouts="payload.timeouts" />

        <db-planner-statistics-section
          v-if="payload.planner_statistics"
          :planner-statistics="payload.planner_statistics"
          class="gl-mt-5"
        />
      </template>
    </gl-card>
  </div>
</template>
