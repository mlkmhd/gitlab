<script>
import { GlBadge, GlLink, GlSprintf, GlTableLite } from '@gitlab/ui';
import { formatNumber, s__, sprintf } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import { numberToHumanSize } from '~/lib/utils/number_utils';
import { approximateDuration } from '~/lib/utils/datetime/date_calculation_utility';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { severityVariant } from '../utils';
import DiagnosticsSection from './diagnostics_section.vue';

// Gitlab::Database::Diagnostics::Checks::PlannerStatistics statuses and kinds.
const STATUS_MISSING = 'missing';
const STATUS_STALE = 'stale';
const KIND_PARTITIONED_TABLE = 'partitioned_table';

const STATUS_SEVERITIES = { [STATUS_MISSING]: 'error', [STATUS_STALE]: 'warning' };

const PLANNER_STATISTICS_DOCS_URL = helpPagePath('administration/postgresql/vacuum', {
  anchor: 'planner-statistics-findings',
});

export default {
  name: 'DbPlannerStatisticsSection',
  components: { GlBadge, GlLink, GlSprintf, GlTableLite, DiagnosticsSection, TimeAgoTooltip },
  props: {
    plannerStatistics: {
      type: Object,
      required: true,
    },
  },
  computed: {
    findings() {
      return this.plannerStatistics.findings || [];
    },
    relations() {
      return this.plannerStatistics.relations || [];
    },
    hasRelations() {
      return this.relations.length > 0;
    },
    hasUnrecordedAnalyze() {
      return this.relations.some((relation) => this.unrecordedAnalyze(relation));
    },
    cappedNote() {
      return sprintf(this.$options.i18n.capped, { count: this.rows.length });
    },
    // Relations arrive with problems first, then by size, so no ordering is applied here.
    rows() {
      return this.relations.map((relation) => ({
        name: `${relation.schema_name}.${relation.table_name}`,
        kind: this.kindLabel(relation),
        heapSize: numberToHumanSize(relation.heap_bytes),
        estimatedRows: this.estimatedRowsLabel(relation),
        lastAnalyze: this.lastAnalyzeLabel(relation),
        interval: relation.analyze_interval
          ? approximateDuration(relation.analyze_interval)
          : s__('DatabaseDiagnostics|Not applicable'),
        status: relation.status,
      }));
    },
  },
  methods: {
    kindLabel(relation) {
      return relation.kind === KIND_PARTITIONED_TABLE
        ? s__('DatabaseDiagnostics|Partitioned table')
        : s__('DatabaseDiagnostics|Table');
    },
    estimatedRowsLabel(relation) {
      if (relation.estimated_rows == null) return s__('DatabaseDiagnostics|Not available');

      return formatNumber(relation.estimated_rows);
    },
    // "never" only when the catalog says so; a missing age on an analyzed table
    // means PostgreSQL reset the statistics counters since.
    unrecordedAnalyze(relation) {
      return relation.analyze_age_seconds == null && relation.status !== STATUS_MISSING;
    },
    lastAnalyzeLabel(relation) {
      if (relation.analyze_age_seconds != null) {
        return sprintf(s__('DatabaseDiagnostics|%{duration} ago'), {
          duration: approximateDuration(relation.analyze_age_seconds),
        });
      }

      return this.unrecordedAnalyze(relation)
        ? s__('DatabaseDiagnostics|Not recorded')
        : s__('DatabaseDiagnostics|Never');
    },
    statusVariant(status) {
      return severityVariant(STATUS_SEVERITIES[status]);
    },
    statusLabel(status) {
      return status === STATUS_MISSING
        ? s__('DatabaseDiagnostics|Missing')
        : s__('DatabaseDiagnostics|Stale');
    },
  },
  fields: [
    { key: 'name', label: s__('DatabaseDiagnostics|Relation') },
    { key: 'kind', label: s__('DatabaseDiagnostics|Type') },
    { key: 'heapSize', label: s__('DatabaseDiagnostics|Heap size') },
    { key: 'estimatedRows', label: s__('DatabaseDiagnostics|Estimated rows') },
    { key: 'lastAnalyze', label: s__('DatabaseDiagnostics|Last analyzed') },
    { key: 'interval', label: s__('DatabaseDiagnostics|Expected interval') },
    { key: 'status', label: s__('DatabaseDiagnostics|Status') },
  ],
  plannerStatisticsDocsUrl: PLANNER_STATISTICS_DOCS_URL,
  i18n: {
    title: s__('DatabaseDiagnostics|Planner statistics'),
    description: s__(
      'DatabaseDiagnostics|Large tables with no planner statistics on record, and large partitioned tables, which autovacuum never analyzes. Problems are listed first.',
    ),
    statsReset: s__(
      'DatabaseDiagnostics|PostgreSQL reset its statistics counters %{timeAgo}. A table last analyzed before then shows no analyze time.',
    ),
    empty: s__('DatabaseDiagnostics|No table or partitioned table is large enough to report.'),
    capped: s__(
      'DatabaseDiagnostics|Only the first %{count} relations are listed. The findings above count every table.',
    ),
    learnMore: s__('DatabaseDiagnostics|Learn more about planner statistics findings.'),
    ok: s__('DatabaseDiagnostics|OK'),
  },
};
</script>

<template>
  <section>
    <diagnostics-section
      :title="$options.i18n.title"
      :severity="plannerStatistics.severity"
      :findings="findings"
      :foldable="hasRelations"
      testid-prefix="planner-statistics"
    >
      <p class="gl-text-sm gl-text-subtle">{{ $options.i18n.description }}</p>

      <p
        v-if="plannerStatistics.stats_reset && hasUnrecordedAnalyze"
        class="gl-text-sm gl-text-subtle"
        data-testid="planner-statistics-stats-reset"
      >
        <gl-sprintf :message="$options.i18n.statsReset">
          <template #timeAgo>
            <time-ago-tooltip :time="plannerStatistics.stats_reset" />
          </template>
        </gl-sprintf>
      </p>

      <gl-table-lite
        :items="rows"
        :fields="$options.fields"
        stacked="md"
        data-testid="planner-statistics-table"
      >
        <template #cell(name)="{ item }">
          <code>{{ item.name }}</code>
        </template>

        <template #cell(status)="{ item }">
          <gl-badge
            v-if="item.status"
            :variant="statusVariant(item.status)"
            :data-testid="`planner-statistics-status-${item.status}`"
          >
            {{ statusLabel(item.status) }}
          </gl-badge>
          <gl-badge v-else variant="success" data-testid="planner-statistics-status-ok">
            {{ $options.i18n.ok }}
          </gl-badge>
        </template>
      </gl-table-lite>

      <p
        v-if="plannerStatistics.relations_capped"
        class="gl-mt-3 gl-text-sm gl-text-subtle"
        data-testid="planner-statistics-capped"
      >
        {{ cappedNote }}
      </p>

      <p class="gl-mt-3 gl-text-sm">
        <gl-link :href="$options.plannerStatisticsDocsUrl" target="_blank">{{
          $options.i18n.learnMore
        }}</gl-link>
      </p>
    </diagnostics-section>

    <p
      v-if="!hasRelations"
      class="gl-mt-3 gl-text-sm gl-text-subtle"
      data-testid="planner-statistics-empty"
    >
      {{ $options.i18n.empty }}
    </p>
  </section>
</template>
