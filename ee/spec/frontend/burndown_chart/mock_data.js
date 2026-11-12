export const day1 = {
  __typename: 'BurnupChartDailyTotals',
  date: '2020-04-08',
  completedCount: 0,
  completedWeight: 0,
  scopeCount: 10,
  scopeWeight: 20,
};

export const day2 = {
  __typename: 'BurnupChartDailyTotals',
  date: '2020-04-09',
  completedCount: 1,
  completedWeight: 1,
  scopeCount: 11,
  scopeWeight: 20,
};

export const day3 = {
  __typename: 'BurnupChartDailyTotals',
  date: '2020-04-10',
  completedCount: 2,
  completedWeight: 4,
  scopeCount: 11,
  scopeWeight: 22,
};

export const day4 = {
  __typename: 'BurnupChartDailyTotals',
  date: '2020-04-11',
  completedCount: 3,
  completedWeight: 5,
  scopeCount: 11,
  scopeWeight: 22,
};

export const reportError = {
  __typename: 'TimeboxReportError',
  code: 'TOO_MANY_EVENTS',
  message: 'Burnup chart could not be generated due to too many events',
};

const getBurnupQueryResponse = (parent, days, error) => ({
  data: {
    [parent]: {
      __typename: parent === 'iteration' ? 'Iteration' : 'Milestone',
      id: `gid://gitlab/${parent === 'iteration' ? 'Iteration' : 'Milestone'}/139072`,
      title: null,
      report: {
        __typename: 'TimeboxReport',
        error,
        burnupTimeSeries: days,
        stats: {
          __typename: 'TimeReportStats',
          total: { __typename: 'TimeboxMetrics', count: 12, weight: 15 },
          complete: { __typename: 'TimeboxMetrics', count: 2, weight: 3 },
          incomplete: { __typename: 'TimeboxMetrics', count: 10, weight: 12 },
        },
      },
    },
  },
});

export const getBurnupQueryIterationSuccess = (days, error = null) =>
  getBurnupQueryResponse('iteration', days, error);

export const getBurnupQueryMilestoneSuccess = (days, error = null) =>
  getBurnupQueryResponse('milestone', days, error);
