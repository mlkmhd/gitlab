import { InMemoryCache } from '@apollo/client/core';
import getUserSubscriptionUsageQuery from 'ee/usage_quotas/usage_billing/users/show/graphql/get_user_subscription_usage.query.graphql';
import getUserSubscriptionUsageEventsQuery from 'ee/usage_quotas/usage_billing/users/show/graphql/get_user_subscription_usage_events.query.graphql';
import { usageBillingCacheConfig } from 'ee/usage_quotas/usage_billing/apollo_cache_config';

const USER_ID = 'gid://gitlab/User/42';
const THIS_MONTH = { startDate: '2026-11-01', endDate: '2026-11-30' };
const LAST_MONTH = { startDate: '2026-10-01', endDate: '2026-10-31' };

const withUser = (user, rootFields = {}) => ({
  subscriptionUsage: {
    __typename: 'GitlabSubscriptionUsage',
    ...rootFields,
    usersUsage: {
      __typename: 'GitlabSubscriptionUsageUsersUsage',
      users: {
        __typename: 'GitlabSubscriptionUsageUserConnection',
        nodes: [{ __typename: 'GitlabSubscriptionUsageUser', id: USER_ID, ...user }],
      },
    },
  },
});

const usageData = ({ startDate, endDate }, creditsUsed) =>
  withUser(
    {
      name: 'Alice Johnson',
      username: 'alice_johnson',
      avatarUrl: 'https://www.gravatar.com/avatar/1',
      usage: {
        __typename: 'GitlabSubscriptionUsageUserUsage',
        totalCreditsUsed: creditsUsed,
        nonBillableCreditsUsed: 0,
      },
      usedFlowTypes: [
        { __typename: 'GitlabSubscriptionUsageFlowTypeInfo', id: 'chat', title: 'Agentic Chat' },
      ],
    },
    {
      enabled: true,
      startDate,
      endDate,
    },
  );

const eventsData = (timestamp) =>
  withUser({
    events: {
      __typename: 'GitlabSubscriptionUsageUserEventConnection',
      nodes: [
        {
          __typename: 'GitlabSubscriptionUsageUserEvent',
          timestamp,
          flowType: 'Agentic Chat',
          location: null,
          creditsUsed: 10,
          sessionLink: null,
          billable: true,
          skipReason: null,
        },
      ],
      pageInfo: {
        __typename: 'PageInfo',
        hasNextPage: false,
        hasPreviousPage: false,
        startCursor: null,
        endCursor: null,
      },
    },
  });

const usageVariables = (range) => ({ username: 'alice_johnson', ...range });
const eventsVariables = (range) => ({ ...usageVariables(range), flowTypes: null, first: 20 });

describe('usageBillingCacheConfig', () => {
  let cache;

  const writeRange = (range, creditsUsed, timestamp) => {
    cache.writeQuery({
      query: getUserSubscriptionUsageQuery,
      variables: usageVariables(range),
      data: usageData(range, creditsUsed),
    });
    cache.writeQuery({
      query: getUserSubscriptionUsageEventsQuery,
      variables: eventsVariables(range),
      data: eventsData(timestamp),
    });
  };

  const readUsage = (range) =>
    cache.readQuery({ query: getUserSubscriptionUsageQuery, variables: usageVariables(range) });
  const readEvents = (range) =>
    cache.readQuery({
      query: getUserSubscriptionUsageEventsQuery,
      variables: eventsVariables(range),
    });

  beforeEach(() => {
    cache = new InMemoryCache(usageBillingCacheConfig);
  });

  it('keeps the usage result complete after the events query writes the same range', () => {
    writeRange(THIS_MONTH, 50, '2026-11-02T10:00:00Z');

    expect(readUsage(THIS_MONTH)).toEqual(usageData(THIS_MONTH, 50));
    expect(readEvents(THIS_MONTH)).toEqual(eventsData('2026-11-02T10:00:00Z'));
  });

  it('keeps a separate copy of the user for each date range', () => {
    writeRange(THIS_MONTH, 50, '2026-11-02T10:00:00Z');
    writeRange(LAST_MONTH, 30, '2026-10-02T10:00:00Z');

    expect(readUsage(THIS_MONTH)).toEqual(usageData(THIS_MONTH, 50));
    expect(readEvents(THIS_MONTH)).toEqual(eventsData('2026-11-02T10:00:00Z'));
    expect(readUsage(LAST_MONTH)).toEqual(usageData(LAST_MONTH, 30));
    expect(readEvents(LAST_MONTH)).toEqual(eventsData('2026-10-02T10:00:00Z'));
  });

  it('stores the user once by ID', () => {
    writeRange(THIS_MONTH, 50, '2026-11-02T10:00:00Z');
    writeRange(LAST_MONTH, 30, '2026-10-02T10:00:00Z');

    const userEntries = Object.keys(cache.extract()).filter((key) =>
      key.startsWith('GitlabSubscriptionUsageUser:'),
    );
    expect(userEntries).toEqual([`GitlabSubscriptionUsageUser:${USER_ID}`]);
  });
});
