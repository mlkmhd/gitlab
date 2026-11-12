import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlKeysetPagination, GlAlert, GlAvatar, GlLoadingIcon } from '@gitlab/ui';
import UsageBillingUserDashboardApp from 'ee/usage_quotas/usage_billing/users/show/components/app.vue';
import EventsTable from 'ee/usage_quotas/usage_billing/users/show/components/events_table.vue';
import FlowTypeFilter from 'ee/usage_quotas/usage_billing/users/show/components/flow_type_filter.vue';
import DateRangeFilter from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/shared/components/date_range_filter.vue';
import { shallowMountExtended, mountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { logError } from '~/lib/logger';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import getUserSubscriptionUsageQuery from 'ee/usage_quotas/usage_billing/users/show/graphql/get_user_subscription_usage.query.graphql';
import getUserSubscriptionUsageEventsQuery from 'ee/usage_quotas/usage_billing/users/show/graphql/get_user_subscription_usage_events.query.graphql';
import createMockApollo from 'helpers/mock_apollo_helper';
import {
  THIS_MONTH,
  LAST_MONTH,
  CUSTOM,
  LAST_7_DAYS,
} from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/shared/components/constants';
import { mockDataWithPool, mockDataEvents, mockDisabledStateData } from '../mock_data';

jest.mock('~/lib/logger');
jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

const PAGE_SIZE = 20;

describe('UsageBillingUserDashboardApp', () => {
  /** @type {import('helpers/vue_test_utils_helper').ExtendedWrapper} */
  let wrapper;
  /** @type { MockAdapter } */

  const MOCK_USER = mockDataWithPool.data.subscriptionUsage.usersUsage.users.nodes[0];
  const MOCK_USER_EVENTS = mockDataEvents.data.subscriptionUsage.usersUsage.users.nodes[0].events;
  const USERNAME = MOCK_USER.username;

  /** @type {jest.Mock} */
  let mockQueryHandler;
  /** @type {jest.Mock} */
  let mockEventsQueryHandler;

  const createComponent = ({ mountFn = shallowMountExtended, provide = {} } = {}) => {
    wrapper = mountFn(UsageBillingUserDashboardApp, {
      apolloProvider: createMockApollo([
        [getUserSubscriptionUsageQuery, mockQueryHandler],
        [getUserSubscriptionUsageEventsQuery, mockEventsQueryHandler],
      ]),
      provide: {
        username: USERNAME,
        namespacePath: null,
        ...provide,
      },
    });
  };

  const findAlert = () => wrapper.findComponent(GlAlert);
  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findUserAvatar = () => wrapper.findComponent(GlAvatar);
  const findTotalUsageCard = () => wrapper.findByTestId('total-usage-card');
  const findEventsTable = () => wrapper.findComponent(EventsTable);
  const findFlowTypeFilter = () => wrapper.findComponent(FlowTypeFilter);
  const findDateRangeFilter = () => wrapper.findComponent(DateRangeFilter);
  const findDisabledStateAlert = () => wrapper.findByTestId('usage-billing-disabled-alert');
  const findPagination = () => wrapper.findComponent(GlKeysetPagination);
  const findEventsSection = () => wrapper.findByTestId('usage-billing-user-events-list');

  beforeEach(() => {
    window.gon = {
      display_gitlab_credits_user_data: true,
      subscriptions_url: 'https://customers.gitlab.com/',
    };
  });

  beforeEach(() => {
    mockQueryHandler = jest.fn();
    mockEventsQueryHandler = jest.fn();
  });

  describe('loading state', () => {
    beforeEach(async () => {
      mockQueryHandler.mockImplementation(() => new Promise(() => {}));
      mockEventsQueryHandler.mockImplementation(() => new Promise(() => {}));
      createComponent();
      await waitForPromises();
    });

    it('shows only a loading icon when fetching data', () => {
      expect(findLoadingIcon().exists()).toBe(true);
    });
  });

  describe('loaded state', () => {
    beforeEach(async () => {
      mockQueryHandler.mockResolvedValue(mockDataWithPool);
      mockEventsQueryHandler.mockResolvedValue(mockDataEvents);
      createComponent();
      await waitForPromises();
    });

    it('calls the subscription usage API with username and default date range', () => {
      expect(mockQueryHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          username: USERNAME,
          startDate: THIS_MONTH.startDate,
          endDate: THIS_MONTH.endDate,
        }),
      );
    });

    it('calls the events API with pagination, filter, and default date range variables', () => {
      expect(mockEventsQueryHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          username: USERNAME,
          first: PAGE_SIZE,
          last: null,
          after: null,
          before: null,
          startDate: THIS_MONTH.startDate,
          endDate: THIS_MONTH.endDate,
        }),
      );
    });

    describe('header', () => {
      it('renders user avatar', () => {
        expect(findUserAvatar().exists()).toBe(true);
        expect(findUserAvatar().props('src')).toBe(MOCK_USER.avatarUrl);
      });

      it('renders user info', () => {
        expect(wrapper.text()).toContain(MOCK_USER.name);
        expect(wrapper.text()).toContain(`@${USERNAME}`);
      });
    });

    describe('usage cards', () => {
      it('renders billable plus non-billable credits used', () => {
        const card = findTotalUsageCard();

        // 9999 billable + 501 non-billable
        expect(card.exists()).toBe(true);
        expect(card.text()).toContain('10.5k');
      });

      it('renders billable credits only when the non-billable figure is unavailable', async () => {
        const user = mockDataWithPool.data.subscriptionUsage.usersUsage.users.nodes[0];
        mockQueryHandler.mockResolvedValue({
          data: {
            subscriptionUsage: {
              ...mockDataWithPool.data.subscriptionUsage,
              usersUsage: {
                users: {
                  nodes: [
                    {
                      ...user,
                      usage: {
                        ...user.usage,
                        totalCreditsUsed: 9500,
                        nonBillableCreditsUsed: null,
                      },
                    },
                  ],
                },
              },
            },
          },
        });
        createComponent();
        await waitForPromises();

        expect(findTotalUsageCard().text()).toContain('9.5k');
      });
    });

    describe('events', () => {
      it('renders the events table', () => {
        const eventsTable = findEventsTable();

        expect(eventsTable.exists()).toBe(true);
        expect(eventsTable.props('events')).toStrictEqual(MOCK_USER_EVENTS.nodes);
      });

      describe('filters', () => {
        describe('flow type filtering', () => {
          const ALL_FLOW_TYPES = [
            'ai_catalog_agent',
            'ai_gateway_proxy_use',
            'amazon_q_integration',
            'analytics_agent',
            'chat',
            'code_review',
            'code_suggestions',
            'convert_to_gl_ci',
            'dap_feature_legacy',
            'developer',
            'duo_chat_classic',
            'duo_planner',
            'fix_pipeline',
            'issue_to_merge_request',
            'orbit_code_intelligence',
            'orbit_core',
            'orbit_dws',
            'orbit_frontend',
            'orbit_mcp',
            'orbit_rest',
            'other_ai_usage',
            'resolve_sast_vulnerability',
            'sast_fp_detection',
            'secrets_fp_detection',
            'security_analyst_agent',
            'software_development',
          ];

          beforeEach(async () => {
            createComponent({ mountFn: mountExtended });
            await waitForPromises();
          });

          it('renders the flow type filter with all used flow types selected', () => {
            const flowTypeFilter = findFlowTypeFilter();

            expect(flowTypeFilter.exists()).toBe(true);
            expect(flowTypeFilter.props('appliedFlowTypes')).toEqual(ALL_FLOW_TYPES);
          });

          it('calls the graphql query with no flowTypes selected on initial load', () => {
            expect(mockEventsQueryHandler).toHaveBeenCalledWith(
              expect.objectContaining({
                flowTypes: null,
              }),
            );
          });

          it('updates the graphql query when flow types are applied', async () => {
            mockEventsQueryHandler.mockClear();

            findFlowTypeFilter().vm.$emit('apply', ['software_development', 'code_review']);
            await nextTick();

            expect(mockEventsQueryHandler).toHaveBeenCalledWith(
              expect.objectContaining({
                namespacePath: null,
                username: 'alice_johnson',
                flowTypes: ['software_development', 'code_review'],
                first: PAGE_SIZE,
                after: null,
                before: null,
                last: null,
              }),
            );
          });

          it("won't fetch events the second time, when all items are selected again", async () => {
            // Preselect some flow types
            findFlowTypeFilter().vm.$emit('apply', ['software_development', 'code_review']);
            await nextTick();

            mockEventsQueryHandler.mockClear();

            findFlowTypeFilter().vm.$emit('apply', ALL_FLOW_TYPES);
            await nextTick();

            expect(mockEventsQueryHandler).not.toHaveBeenCalled();
          });

          it('resets pagination when applying flow type filter', async () => {
            // First navigate to next page
            mockEventsQueryHandler.mockClear();
            findPagination().vm.$emit('next', '42');
            await nextTick();

            expect(mockEventsQueryHandler).toHaveBeenCalledWith(
              expect.objectContaining({
                after: '42',
              }),
            );

            await waitForPromises();

            // Then apply filter
            mockEventsQueryHandler.mockClear();
            findFlowTypeFilter().vm.$emit('apply', ['software_development']);
            await nextTick();

            // Should reset pagination to first page
            expect(mockEventsQueryHandler).toHaveBeenCalledWith(
              expect.objectContaining({
                flowTypes: ['software_development'],
                first: PAGE_SIZE,
                after: null,
                before: null,
                last: null,
              }),
            );
          });

          it('passes flow types from user data to filter component', () => {
            const flowTypeFilter = findFlowTypeFilter();
            const expectedFlowTypes = MOCK_USER.usedFlowTypes.map((flowType) => ({
              value: flowType.id,
              text: flowType.title,
            }));

            expect(flowTypeFilter.props('flowTypes')).toEqual(expectedFlowTypes);
          });
        });

        describe('date range filtering', () => {
          const LAST_MONTH_RANGE = {
            value: 'last_month',
            startDate: '2026-10-01',
            endDate: '2026-10-31',
          };

          beforeEach(async () => {
            createComponent({ mountFn: shallowMountExtended });
            await waitForPromises();
          });

          it('does not set the flow type filter to loading once usage has loaded', () => {
            expect(findFlowTypeFilter().props('loading')).toBe(false);
          });

          it('renders the date range filter with the default This Month selection', () => {
            const filter = findDateRangeFilter();

            expect(filter.exists()).toBe(true);
            expect(filter.props('value')).toMatchObject({ value: THIS_MONTH.value });
          });

          it('refetches both queries when the date range changes', async () => {
            mockQueryHandler.mockClear();
            mockEventsQueryHandler.mockClear();

            findDateRangeFilter().vm.$emit('input', LAST_MONTH_RANGE);
            await nextTick();

            expect(mockQueryHandler).toHaveBeenCalledWith(
              expect.objectContaining({
                startDate: LAST_MONTH_RANGE.startDate,
                endDate: LAST_MONTH_RANGE.endDate,
              }),
            );
            expect(mockEventsQueryHandler).toHaveBeenCalledWith(
              expect.objectContaining({
                startDate: LAST_MONTH_RANGE.startDate,
                endDate: LAST_MONTH_RANGE.endDate,
              }),
            );
          });

          it('keeps the filters and shows loading states while refetching', async () => {
            mockQueryHandler.mockImplementation(() => new Promise(() => {}));
            findDateRangeFilter().vm.$emit('input', LAST_MONTH_RANGE);
            await nextTick();

            expect(findDateRangeFilter().exists()).toBe(true);
            expect(findTotalUsageCard().findComponent(GlLoadingIcon).exists()).toBe(true);
            expect(findFlowTypeFilter().props('loading')).toBe(true);
          });

          it('resets the flow type filter when the date range changes', async () => {
            findFlowTypeFilter().vm.$emit('apply', ['software_development']);
            await nextTick();

            mockEventsQueryHandler.mockClear();
            findDateRangeFilter().vm.$emit('input', LAST_MONTH_RANGE);
            await nextTick();

            expect(mockEventsQueryHandler).toHaveBeenCalledWith(
              expect.objectContaining({ flowTypes: null }),
            );
          });

          it('resets pagination when the date range changes', async () => {
            mockEventsQueryHandler.mockClear();
            findPagination().vm.$emit('next', '42');
            await nextTick();
            await waitForPromises();

            mockEventsQueryHandler.mockClear();
            findDateRangeFilter().vm.$emit('input', LAST_MONTH_RANGE);
            await nextTick();

            expect(mockEventsQueryHandler).toHaveBeenCalledWith(
              expect.objectContaining({
                first: PAGE_SIZE,
                after: null,
                before: null,
                last: null,
              }),
            );
          });

          it('does not restrict the custom range min date without a subscription start date', () => {
            expect(findDateRangeFilter().props('customDateRangeMinDate')).toBeNull();
          });

          describe('with a subscription start date', () => {
            // The test clock is 2020-07-06, so LAST_MONTH ends before this date and
            // LAST_7_DAYS starts before it.
            const subscriptionStartDate = '2020-07-01';

            const findOption = (value) =>
              findDateRangeFilter()
                .props('options')
                .find((option) => option.value === value);

            beforeEach(async () => {
              createComponent({ provide: { subscriptionStartDate } });
              await waitForPromises();
            });

            it('passes the subscription start date as the custom range min date', () => {
              expect(findDateRangeFilter().props('customDateRangeMinDate')).toEqual(
                new Date(2020, 6, 1, 0, 0, 0),
              );
            });

            it('drops presets that end before the subscription started', () => {
              expect(findOption(LAST_MONTH.value)).toBeUndefined();
            });

            it('clamps presets that start before the subscription started', () => {
              expect(findOption(LAST_7_DAYS.value)).toMatchObject({
                startDate: subscriptionStartDate,
                endDate: LAST_7_DAYS.endDate,
              });
            });
          });
        });
      });

      describe('pagination', () => {
        beforeEach(async () => {
          createComponent({ mountFn: mountExtended });
          await waitForPromises();
        });

        it('calls the events query on load with pagination variables', () => {
          expect(mockEventsQueryHandler).toHaveBeenCalledWith(
            expect.objectContaining({
              username: USERNAME,
              after: null,
              before: null,
              first: PAGE_SIZE,
              last: null,
            }),
          );
        });

        it('will render the pagination', () => {
          const { hasNextPage, hasPreviousPage, startCursor, endCursor } =
            MOCK_USER_EVENTS.pageInfo;

          expect(findPagination().exists()).toBe(true);
          expect(findPagination().props()).toEqual(
            expect.objectContaining({
              hasNextPage,
              hasPreviousPage,
              startCursor,
              endCursor,
            }),
          );
        });

        it('calls the events query on next page navigation', async () => {
          mockEventsQueryHandler.mockClear();

          findPagination().vm.$emit('next', '42');
          await nextTick();

          expect(mockEventsQueryHandler).toHaveBeenCalledWith(
            expect.objectContaining({
              after: '42',
              before: null,
              first: PAGE_SIZE,
              last: null,
            }),
          );
        });

        it('calls the events query on prev page navigation', async () => {
          mockEventsQueryHandler.mockClear();

          findPagination().vm.$emit('prev', '37');
          await nextTick();

          expect(mockEventsQueryHandler).toHaveBeenCalledWith(
            expect.objectContaining({
              after: null,
              before: '37',
              first: null,
              last: PAGE_SIZE,
            }),
          );
        });
      });

      describe('events loading state', () => {
        beforeEach(async () => {
          mockQueryHandler.mockResolvedValue(mockDataWithPool);
          mockEventsQueryHandler.mockImplementation(() => new Promise(() => {}));
          createComponent({ mountFn: mountExtended });
          await nextTick();
        });

        it('shows loading icon when events are being fetched', () => {
          const eventsSection = findEventsSection();
          const loadingIcon = eventsSection.findComponent(GlLoadingIcon);

          expect(loadingIcon.exists()).toBe(true);
        });

        it('does not show events table while loading', () => {
          const eventsSection = findEventsSection();
          const eventsTable = eventsSection.findComponent(EventsTable);

          expect(eventsTable.exists()).toBe(false);
        });

        it('does not show pagination while loading', () => {
          const eventsSection = findEventsSection();
          const pagination = eventsSection.findComponent(GlKeysetPagination);

          expect(pagination.exists()).toBe(false);
        });
      });

      describe('events error state', () => {
        beforeEach(async () => {
          mockQueryHandler.mockResolvedValue(mockDataWithPool);
          mockEventsQueryHandler.mockRejectedValue(new Error('Failed to fetch events'));
          createComponent({ mountFn: mountExtended });
          await waitForPromises();
        });

        it('shows error alert when events query fails', () => {
          const eventsSection = findEventsSection();
          const alert = eventsSection.findComponent(GlAlert);

          expect(alert.exists()).toBe(true);
          expect(alert.text()).toBe('An error occurred while fetching events list');
        });

        it('clears the error when the date range changes', async () => {
          mockEventsQueryHandler.mockResolvedValue(mockDataEvents);
          findDateRangeFilter().vm.$emit('input', {
            value: 'last_month',
            startDate: '2020-06-01',
            endDate: '2020-06-30',
          });
          await waitForPromises();

          expect(findEventsSection().findComponent(GlAlert).exists()).toBe(false);
          expect(findEventsSection().findComponent(EventsTable).exists()).toBe(true);
        });

        it('clears the error when flow types change and the refetch succeeds', async () => {
          mockEventsQueryHandler.mockResolvedValue(mockDataEvents);
          findFlowTypeFilter().vm.$emit('apply', ['software_development']);
          await waitForPromises();

          expect(findEventsSection().findComponent(GlAlert).exists()).toBe(false);
          expect(findEventsSection().findComponent(EventsTable).exists()).toBe(true);
        });

        it('keeps the error when the refetch fails again', async () => {
          findFlowTypeFilter().vm.$emit('apply', ['software_development']);
          await waitForPromises();

          expect(findEventsSection().findComponent(GlAlert).exists()).toBe(true);
        });

        it('does not show events table on error', () => {
          const eventsSection = findEventsSection();
          const eventsTable = eventsSection.findComponent(EventsTable);

          expect(eventsTable.exists()).toBe(false);
        });

        it('does not show pagination on error', () => {
          const eventsSection = findEventsSection();
          const pagination = eventsSection.findComponent(GlKeysetPagination);

          expect(pagination.exists()).toBe(false);
        });

        it('logs the error to console and Sentry', () => {
          expect(logError).toHaveBeenCalledWith(expect.any(Error));
          expect(captureException).toHaveBeenCalledWith(expect.any(Error));
        });
      });
    });
  });

  describe('disabled state alert', () => {
    describe('when Usage Billing is available', () => {
      beforeEach(async () => {
        mockQueryHandler.mockResolvedValue(mockDataWithPool);
        mockEventsQueryHandler.mockResolvedValue(mockDataEvents);
        createComponent();
        await waitForPromises();
      });

      it('does not render alert if enabled is true', () => {
        expect(findDisabledStateAlert().exists()).toBe(false);
      });

      it('displays all other elements', () => {
        expect(wrapper.findByTestId('usage-billing-user-header').exists()).toBe(true);
        expect(wrapper.findByTestId('usage-billing-user-cards-row').exists()).toBe(true);
        expect(wrapper.findByTestId('usage-billing-user-events-list').exists()).toBe(true);
      });
    });

    describe('when Usage Billing is disabled', () => {
      beforeEach(async () => {
        mockQueryHandler.mockResolvedValue(mockDisabledStateData);
        mockEventsQueryHandler.mockResolvedValue(mockDisabledStateData);
        createComponent();
        await waitForPromises();
      });

      it('renders disabled state alert', () => {
        expect(findDisabledStateAlert().exists()).toBe(true);
      });

      it('hides all other components', () => {
        expect(wrapper.findByTestId('usage-billing-user-header').exists()).toBe(false);
        expect(wrapper.findByTestId('usage-billing-user-cards-row').exists()).toBe(false);
        expect(wrapper.findByTestId('usage-billing-user-events-list').exists()).toBe(false);
      });
    });
  });

  describe('error state', () => {
    beforeEach(async () => {
      mockQueryHandler.mockRejectedValue(new Error('Network Error'));
      mockEventsQueryHandler.mockRejectedValue(new Error('Network Error'));
      createComponent();
      await waitForPromises();
    });

    it('shows error alert when API request fails', () => {
      const alert = findAlert();
      expect(alert.text()).toBe('An error occurred while fetching usage data');
    });

    it('keeps the date range filter available', () => {
      expect(findDateRangeFilter().exists()).toBe(true);
    });

    it('keeps the error when switching to Custom with the same dates', async () => {
      findDateRangeFilter().vm.$emit('input', {
        value: CUSTOM.value,
        startDate: THIS_MONTH.startDate,
        endDate: THIS_MONTH.endDate,
      });
      await waitForPromises();

      expect(findAlert().text()).toBe('An error occurred while fetching usage data');
    });

    it('clears the error when the date range changes', async () => {
      mockQueryHandler.mockResolvedValue(mockDataWithPool);
      mockEventsQueryHandler.mockResolvedValue(mockDataEvents);
      findDateRangeFilter().vm.$emit('input', {
        value: 'last_month',
        startDate: '2020-06-01',
        endDate: '2020-06-30',
      });
      await waitForPromises();

      expect(findAlert().exists()).toBe(false);
      expect(findTotalUsageCard().exists()).toBe(true);
    });

    it('logs the error to console and Sentry', () => {
      expect(logError).toHaveBeenCalledWith(expect.any(Error));
      expect(captureException).toHaveBeenCalledWith(expect.any(Error));
    });
  });
});
