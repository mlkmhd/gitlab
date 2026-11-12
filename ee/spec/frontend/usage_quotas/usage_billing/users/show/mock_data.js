import { merge } from 'lodash-es';

export const mockDataWithPool = {
  data: {
    subscriptionUsage: {
      enabled: true,
      startDate: '2025-08-01',
      endDate: '2025-08-31',

      usersUsage: {
        users: {
          nodes: [
            {
              id: 'gid://gitlab/User/42',
              username: 'alice_johnson',
              name: 'Alice Johnson',
              avatarUrl: 'https://www.gravatar.com/avatar/1?s=80&d=identicon',

              usedFlowTypes: [
                {
                  id: 'ai_catalog_agent',
                  title: 'AI Catalog based Agent or Flow',
                },
                {
                  id: 'ai_gateway_proxy_use',
                  title: 'AI Gateway Proxy',
                },
                {
                  id: 'amazon_q_integration',
                  title: 'Duo with Amazon Q',
                },
                {
                  id: 'analytics_agent',
                  title: 'Analytics Agent',
                },
                {
                  id: 'chat',
                  title: 'Agentic Chat',
                },
                {
                  id: 'code_review',
                  title: 'Code Review Flow',
                },
                {
                  id: 'code_suggestions',
                  title: 'Code Suggestions',
                },
                {
                  id: 'convert_to_gl_ci',
                  title: 'Convert to GitLab CI/CD Flow',
                },
                {
                  id: 'dap_feature_legacy',
                  title: 'DAP Feature (Legacy)',
                },
                {
                  id: 'developer',
                  title: 'Developer Flow',
                },
                {
                  id: 'duo_chat_classic',
                  title: 'Duo Chat (Classic)',
                },
                {
                  id: 'duo_planner',
                  title: 'Duo Planner',
                },
                {
                  id: 'fix_pipeline',
                  title: 'Fix Pipeline Flow',
                },
                {
                  id: 'issue_to_merge_request',
                  title: 'Issue to Merge Request Flow',
                },
                {
                  id: 'orbit_code_intelligence',
                  title: 'Orbit - Code Intelligence',
                },
                {
                  id: 'orbit_core',
                  title: 'Orbit - Core',
                },
                {
                  id: 'orbit_dws',
                  title: 'Orbit - Duo Agent Platform',
                },
                {
                  id: 'orbit_frontend',
                  title: 'Orbit - Frontend',
                },
                {
                  id: 'orbit_mcp',
                  title: 'Orbit - MCP',
                },
                {
                  id: 'orbit_rest',
                  title: 'Orbit - REST',
                },
                {
                  id: 'other_ai_usage',
                  title: 'Other AI Usage',
                },
                {
                  id: 'resolve_sast_vulnerability',
                  title: 'SAST Vulnerability Resolution Flow',
                },
                {
                  id: 'sast_fp_detection',
                  title: 'SAST FP Detection Flow',
                },
                {
                  id: 'secrets_fp_detection',
                  title: 'Secrets FP Detection',
                },
                {
                  id: 'security_analyst_agent',
                  title: 'Security Analyst Agent',
                },
                {
                  id: 'software_development',
                  title: 'Software Development Flow',
                },
              ],

              usage: {
                totalCreditsUsed: 9999,
                nonBillableCreditsUsed: 501,
              },
            },
          ],
        },
      },
    },
  },
};

export const mockDataEvents = {
  data: {
    subscriptionUsage: {
      usersUsage: {
        users: {
          nodes: [
            {
              id: 'gid://gitlab/User/42',
              events: {
                nodes: [
                  {
                    timestamp: '2025-01-21T16:42:38Z',
                    flowType: 'Software Development Flow',
                    location: {
                      __typename: 'Project',
                      id: '1',
                      name: 'frontend-app',
                      webUrl: 'http://localhost:3000/frontend-app',
                    },
                    creditsUsed: 44000,
                    sessionLink: 'http://localhost:3000/frontend-app/-/automate/agent-sessions/101',
                    billable: true,
                    skipReason: null,
                  },
                  {
                    timestamp: '2025-01-21T16:41:15Z',
                    flowType: 'Convert to GitLab CI/CD Flow',
                    location: {
                      __typename: 'Group',
                      id: '2',
                      name: 'group-app',
                      webUrl: 'http://localhost:3000/group-app',
                    },
                    creditsUsed: 6.24,
                    sessionLink: null,
                    billable: false,
                    skipReason: 'promo',
                  },
                  {
                    timestamp: '2025-01-21T16:40:22Z',
                    flowType: 'Agentic Chat',
                    location: {
                      __typename: 'Project',
                      id: '1',
                      name: 'frontend-app',
                      webUrl: 'http://localhost:3000/frontend-app',
                    },
                    creditsUsed: 0,
                    sessionLink: null,
                    billable: true,
                    skipReason: null,
                  },
                  {
                    timestamp: '2025-01-21T16:39:45Z',
                    flowType: 'Code Review Flow',
                    location: {
                      __typename: 'Group',
                      id: '2',
                      name: 'group-app',
                      webUrl: 'http://localhost:3000/group-app',
                    },
                    creditsUsed: null,
                    sessionLink: null,
                    billable: true,
                    skipReason: null,
                  },
                  {
                    timestamp: '2025-01-21T16:38:12Z',
                    flowType: 'Fix Pipeline Flow',
                    location: {
                      __typename: 'Project',
                      id: '1',
                      name: 'frontend-app',
                      webUrl: 'http://localhost:3000/frontend-app',
                    },
                    creditsUsed: 82.33333,
                    sessionLink: null,
                    billable: true,
                    skipReason: null,
                  },
                  {
                    timestamp: '2025-01-21T16:37:33Z',
                    flowType: 'SAST Vulnerability Resolution Flow',
                    location: null,
                    creditsUsed: 55,
                    sessionLink: null,
                    billable: true,
                    skipReason: null,
                  },
                  {
                    timestamp: '2025-01-21T16:36:58Z',
                    flowType: 'SAST FP Detection Flow',
                    location: {
                      __typename: 'Project',
                      id: '1',
                      name: 'frontend-app',
                      webUrl: 'http://localhost:3000/frontend-app',
                    },
                    creditsUsed: 26,
                    sessionLink: null,
                    billable: true,
                    skipReason: null,
                  },
                  {
                    timestamp: '2025-01-21T16:35:41Z',
                    flowType: 'AI Catalog based Agent or Flow',
                    location: {
                      __typename: 'Group',
                      id: '2',
                      name: 'group-app',
                      webUrl: 'http://localhost:3000/group-app',
                    },
                    creditsUsed: 74,
                    sessionLink: null,
                    billable: true,
                    skipReason: null,
                  },
                  {
                    timestamp: '2025-01-21T16:34:27Z',
                    flowType: 'Developer Flow',
                    location: {
                      __typename: 'Project',
                      id: '1',
                      name: 'frontend-app',
                      webUrl: 'http://localhost:3000/frontend-app',
                    },
                    creditsUsed: 51,
                    sessionLink: null,
                    billable: true,
                    skipReason: null,
                  },
                  {
                    timestamp: '2025-01-21T16:33:05Z',
                    flowType: 'Other AI Usage',
                    location: {
                      __typename: 'Project',
                      id: '1',
                      name: 'frontend-app',
                      webUrl: 'http://localhost:3000/frontend-app',
                    },
                    creditsUsed: 70,
                    sessionLink: null,
                    billable: true,
                    skipReason: null,
                  },
                  {
                    timestamp: '2025-01-21T16:31:52Z',
                    flowType: 'Other AI Usage',
                    location: {
                      __typename: 'Project',
                      id: '1',
                      name: 'frontend-app',
                      webUrl: 'http://localhost:3000/frontend-app',
                    },
                    creditsUsed: 15,
                    sessionLink: null,
                    billable: true,
                    skipReason: null,
                  },
                ],
                pageInfo: {
                  hasNextPage: true,
                  hasPreviousPage: false,
                  startCursor: null,
                  endCursor: 'endCursor',
                  __typename: 'PageInfo',
                },
              },
            },
          ],
        },
      },
    },
  },
};

export const mockEmptyData = {
  data: {
    subscriptionUsage: {
      ...mockDataWithPool.data.subscriptionUsage,

      usersUsage: {
        users: {
          ...mockDataWithPool.data.subscriptionUsage.usersUsage.users,
          nodes: [
            {
              ...mockDataWithPool.data.subscriptionUsage.usersUsage.users.nodes[0],

              usage: {
                totalCreditsUsed: 0,
              },
            },
          ],
        },
      },
    },
  },
};

export const mockEmptyDataEvents = {
  data: {
    subscriptionUsage: {
      usersUsage: {
        users: {
          nodes: [
            {
              id: 'gid://gitlab/User/42',
              events: {
                nodes: [],
                pageInfo: {
                  hasNextPage: false,
                  hasPreviousPage: false,
                  startCursor: null,
                  endCursor: null,
                  __typename: 'PageInfo',
                },
              },
            },
          ],
        },
      },
    },
  },
};

export const mockNullData = merge({}, mockEmptyData, {
  data: {
    subscriptionUsage: {
      usersUsage: {
        users: {
          nodes: [
            {
              id: 'gid://gitlab/User/42',
              username: 'alice_johnson',
              name: 'Alice Johnson',
              avatarUrl: 'https://www.gravatar.com/avatar/1?s=80&d=identicon',
              usage: {
                totalCreditsUsed: null,
                __typename: 'GitlabSubscriptionUsageUserUsage',
              },
              __typename: 'GitlabSubscriptionUsageUser',
            },
          ],
          __typename: 'GitlabSubscriptionUsageUserConnection',
        },
        __typename: 'GitlabSubscriptionUsageUsersUsage',
      },
      __typename: 'GitlabSubscriptionUsage',
    },
  },
});

export const mockNullDataEvents = {
  data: {
    subscriptionUsage: {
      usersUsage: {
        users: {
          nodes: [
            {
              id: 'gid://gitlab/User/42',
              events: {
                nodes: [],
                pageInfo: {
                  hasNextPage: false,
                  hasPreviousPage: false,
                  startCursor: null,
                  endCursor: null,
                  __typename: 'PageInfo',
                },
              },
            },
          ],
        },
      },
    },
  },
};

export const mockDisabledStateData = {
  data: {
    subscriptionUsage: {
      ...mockDataWithPool.data.subscriptionUsage,
      enabled: false,
    },
  },
};
