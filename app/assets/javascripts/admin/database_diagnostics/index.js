import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import CombinedDiagnostics from './components/combined_diagnostics.vue';
import PreUpgradeChecks from './components/pre_upgrade_checks.vue';

const parseDatabases = (json) => {
  try {
    return JSON.parse(json);
  } catch {
    return { databases: {} };
  }
};

export const initDatabaseDiagnosticsApp = () => {
  const el = document.getElementById('js-database-diagnostics');

  if (!el) return false;

  const { runCollationCheckUrl, collationCheckResultsUrl, databaseInformation } = el.dataset;

  return initVueApp({
    el,
    name: 'DatabaseDiagnosticsView',
    provide: {
      runCollationCheckUrl,
      collationCheckResultsUrl,
      databaseInformation: parseDatabases(databaseInformation),
    },
    component: CombinedDiagnostics,
  });
};

export const initDatabasePreUpgradeChecksApp = () => {
  const el = document.getElementById('js-database-pre-upgrade-checks');

  if (!el) return false;

  const {
    runSchemaCheckUrl,
    schemaCheckResultsUrl,
    runLfkBacklogCheckUrl,
    lfkBacklogCheckResultsUrl,
    searchPathInformation,
  } = el.dataset;

  return initVueApp({
    el,
    name: 'DatabasePreUpgradeChecksView',
    provide: {
      runSchemaCheckUrl,
      schemaCheckResultsUrl,
      runLfkBacklogCheckUrl,
      lfkBacklogCheckResultsUrl,
      searchPathInformation: parseDatabases(searchPathInformation),
    },
    component: PreUpgradeChecks,
  });
};
