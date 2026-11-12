import jsYaml from 'js-yaml';
import { s__ } from '~/locale';
import { nDaysBefore, toISODateFormat } from '~/lib/utils/datetime_utility';
import {
  dateRangeDayCount,
  dateRangeGranularity,
  resolveDateRangeFilter,
} from '~/explore/analytics_dashboards/components/utils';
import { DATE_RANGE_OPTION_LAST_30_DAYS } from '~/explore/analytics_dashboards/components/constants';
import { DISPLAY_TYPES, MODE_ANALYTICS } from '~/glql/constants';
import { parseYAML } from '~/glql/core/parser';

// A preset carries its previous window already; only a custom range derives one. GLQL reads
// both bounds as whole days, so the length counts both ends and the previous window closes
// the day before this one opens.
export const previousDateRange = ({ startDate, endDate, previousRange }) => {
  if (previousRange) return previousRange;

  const length = dateRangeDayCount({ startDate, endDate });

  return {
    startDate: nDaysBefore(startDate, length, { utc: true }),
    endDate: nDaysBefore(endDate, length, { utc: true }),
  };
};

// A GLQL query names its own date field (`timestamp` here, `merged` there), so the panel
// declares where the dashboard's date range goes instead of this source guessing:
//   query: type = AiUsageEvent and timestamp >= "%{startDate}" and timestamp <= "%{endDate}"
// With `extendToPreviousPeriod` the range starts where the previous period does, so a panel
// that compares each date bucket with the one before it has both periods to compare.
export const dateRangeVariables = (dateRange, extendToPreviousPeriod = false) => {
  const { startDate } = extendToPreviousPeriod ? previousDateRange(dateRange) : dateRange;

  return {
    startDate: toISODateFormat(startDate, true),
    endDate: toISODateFormat(dateRange.endDate, true),
  };
};

// Only the names given are substituted, so any other `%{...}` the query holds reaches the
// GLQL compiler as the author wrote it.
export const interpolate = (glql, variables) =>
  Object.entries(variables).reduce(
    (query, [name, value]) => query.replaceAll(`%{${name}}`, value),
    glql,
  );

// The same block broken down by one more dimension, for the rows a table nests under its own.
// Nested rows show their dimension in the first column, which has to be a dimension too.
export const withDimension = (glql, dimension) => {
  const { query, config } = parseYAML(glql);

  if (config.display !== DISPLAY_TYPES.TABLE) {
    throw new Error(s__('Glql|`expandRowsBy` is only supported for the table display type.'));
  }
  if (config.mode !== MODE_ANALYTICS) {
    throw new Error(s__('Glql|`expandRowsBy` is only supported in analytics mode.'));
  }
  if (!config.dimensions) {
    throw new Error(s__('Glql|`expandRowsBy` needs the query to have at least one dimension.'));
  }

  const dimensions = `${config.dimensions}, ${dimension}`;

  return jsYaml.safeDump({ ...config, dimensions, query });
};

// Both bounds have to move for the previous window to be a window: a query that pins only
// its start would run its comparison up to today, over the very period it is compared with.
const usesWholeDateRange = (glql, variables) =>
  Object.keys(variables).every((name) => glql.includes(`%{${name}}`));

/**
 * Passes a GLQL query string through to the visualization, resolving the dashboard's
 * date range filter into it.
 *
 * Unlike other data sources, GLQL panels don't fetch data here: the `GlqlResolver`
 * rendered by the `Glql` visualization parses and executes the query itself. This
 * source surfaces the query string (stored in the panel's `data.query`) as the `data`
 * prop the visualization receives, with any date range placeholders substituted first.
 *
 * GLQL reads an absolute bound as the whole day (`timestamp <= "2026-09-02"` compiles to
 * `timestampTo: "2026-09-02 23:59"`), so the range needs no end-exclusive adjustment.
 *
 * A panel with `dateField` gets the range as a binding on that field instead, handed down as
 * the `dateRangeBinding` visualization option. The compiler applies it over any predicate the
 * query already has on the field, so the query needs no placeholders. With `showTrends` the
 * comparison reruns the same query, with the previous period handed down as a binding on that
 * field in the `comparisonDateRangeBinding` option, since the main binding would otherwise
 * re-bind the comparison to the current period.
 *
 * A query with no placeholders is returned untouched, so GLQL panels on dashboards
 * without a date range filter keep the window their own query sets.
 *
 * `%{dynamicGranularity}` resolves to the time bucket size the selected range
 * warrants - `daily`, `weekly` or `monthly` - for panels that bucket by date:
 *   dimensions: created(%{dynamicGranularity})
 * A panel that does not ask for it, such as a stat, is unaffected.
 *
 * `%{rangeDays}` is the length of the selected range in days, for a panel that folds the whole
 * range into one bucket. It doesn't reach the comparison query, so it can't combine with
 * `showTrends`.
 *
 * `extendToPreviousPeriod` starts the panel's date range at the start of the previous period,
 * for the `dateField` binding and `%{startDate}` alike. The comparison covers the previous period
 * only, so the dashboard schema rejects a panel that also sets `showTrends`.
 *
 * The visualization's own `data.query.dateRange` is the window used when the dashboard
 * has no date range filter. The dashboard filter wins when both are set, matching the
 * precedence the other analytics data sources already apply to a panel date range.
 *
 * With `showTrends`, a query that interpolates the whole date range is rerun over the prior
 * window and handed down as the `comparisonQuery` option, which the stat display renders as
 * a trend. A `dateField` panel hands down `comparisonDateRangeBinding` instead.
 *
 * With `expandRowsBy` in the visualization options, the same query broken down by that
 * dimension is handed down as the `breakdownQuery` visualization option, which a table nests
 * under its own rows.
 */
export default function fetch({
  query: { glql = '', dateRange: panelDateRange, dateField, extendToPreviousPeriod } = {},
  filters = {},
  visualizationOptions: { showTrends = false, expandRowsBy = null } = {},
  setVisualizationOverrides = () => {},
} = {}) {
  if (typeof glql !== 'string') {
    throw new Error(s__('Glql|GLQL query must be a string.'));
  }

  if (expandRowsBy != null && (typeof expandRowsBy !== 'string' || !expandRowsBy.trim())) {
    throw new Error(s__('Glql|`expandRowsBy` must name a dimension.'));
  }

  const dateRange = resolveDateRangeFilter(
    { ...filters, dateRangeOption: filters.dateRangeOption || panelDateRange },
    DATE_RANGE_OPTION_LAST_30_DAYS,
  );
  const dateVariables = dateRangeVariables(dateRange, extendToPreviousPeriod);
  const dynamicGranularity = dateRangeGranularity(dateRange);
  const rangeDays = dateRangeDayCount(dateRange);
  const previousRange = previousDateRange(dateRange);

  // One call, because setVisualizationOverrides replaces the options rather than merging them.
  const visualizationOptionOverrides = {};

  if (dateField) {
    visualizationOptionOverrides.dateRangeBinding = {
      field: dateField,
      from: dateVariables.startDate,
      to: dateVariables.endDate,
    };
  }

  if (showTrends) {
    const comparisonRange = dateRangeVariables(previousRange);

    if (dateField) {
      visualizationOptionOverrides.comparisonDateRangeBinding = {
        field: dateField,
        from: comparisonRange.startDate,
        to: comparisonRange.endDate,
      };
    } else if (usesWholeDateRange(glql, dateVariables)) {
      // Checked against the date variables alone: a stat carries no granularity placeholder,
      // requiring one here would cost every trend stat its comparison query.
      visualizationOptionOverrides.comparisonQuery = interpolate(glql, {
        ...comparisonRange,
        dynamicGranularity,
      });
    }
  }

  const resolvedGlql = interpolate(glql, {
    ...dateVariables,
    dynamicGranularity,
    rangeDays,
  });

  if (expandRowsBy) {
    visualizationOptionOverrides.breakdownQuery = withDimension(resolvedGlql, expandRowsBy);
  }

  if (Object.keys(visualizationOptionOverrides).length) {
    setVisualizationOverrides({ visualizationOptionOverrides });
  }

  return resolvedGlql;
}
