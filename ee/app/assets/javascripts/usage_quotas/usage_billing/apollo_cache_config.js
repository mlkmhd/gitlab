// The date range is an argument on the parent subscriptionUsage field, so key the user's
// range-dependent fields by the query's date variables. Queries must name them startDate/endDate.
const byDateRange = (args, { variables: { startDate, endDate } = {} }) =>
  JSON.stringify({ ...args, startDate, endDate });

export const usageBillingCacheConfig = {
  typePolicies: {
    Query: {
      fields: {
        // Shallow-merge so the usage and events queries stop replacing each other's root fields.
        subscriptionUsage: {
          merge: true,
        },
      },
    },
    GitlabSubscriptionUsageUser: {
      fields: {
        usage: { keyArgs: byDateRange },
        usedFlowTypes: { keyArgs: byDateRange },
        events: { keyArgs: byDateRange },
      },
    },
  },
};
