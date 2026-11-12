<script>
import { GlTab, GlTabs } from '@gitlab/ui';
import ActiveSessionHistoryApp from './active_session_history_app.vue';
import CollationCheckerApp from './collation_checker_app.vue';
import DatabaseInformationApp from './database_information_app.vue';
import VacuumInformationApp from './vacuum_information_app.vue';
import AutovacuumConfigApp from './autovacuum_config_app.vue';

export default {
  name: 'CombinedDiagnostics',
  components: {
    ActiveSessionHistoryApp,
    GlTab,
    GlTabs,
    VacuumInformationApp,
    AutovacuumConfigApp,
    CollationCheckerApp,
    DatabaseInformationApp,
  },
};
</script>

<template>
  <gl-tabs sync-active-tab-with-query-params>
    <gl-tab :title="s__('DatabaseDiagnostics|Checks')" query-param-value="checks">
      <div class="gl-mt-5">
        <section class="gl-mb-8">
          <database-information-app />
        </section>

        <vacuum-information-app class="gl-mb-8" />

        <autovacuum-config-app class="gl-mb-8" />

        <section class="gl-mb-8">
          <collation-checker-app />
        </section>
      </div>
    </gl-tab>
    <gl-tab
      :title="s__('DatabaseDiagnostics|Active session history')"
      query-param-value="active-session-history"
      lazy
    >
      <active-session-history-app class="gl-mt-5" />
    </gl-tab>
  </gl-tabs>
</template>
