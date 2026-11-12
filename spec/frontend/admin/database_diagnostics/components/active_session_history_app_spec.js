import { nextTick } from 'vue';
import {
  GlCollapsibleListbox,
  GlDashboardPanel,
  GlDatepicker,
  GlFormGroup,
  GlSkeletonLoader,
} from '@gitlab/ui';
import MockAdapter from 'axios-mock-adapter';
import timezoneMock from 'timezone-mock';
import { useFakeDate } from 'helpers/fake_date';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import axios from '~/lib/utils/axios_utils';
import {
  HTTP_STATUS_INTERNAL_SERVER_ERROR,
  HTTP_STATUS_OK,
  HTTP_STATUS_UNAUTHORIZED,
} from '~/lib/utils/http_status';
import ActiveSessionHistoryApp from '~/admin/database_diagnostics/components/active_session_history_app.vue';
import ActiveSessionHistoryChart from '~/admin/database_diagnostics/components/active_session_history_chart.vue';
import ChartSkeletonLoader from '~/vue_shared/components/resizable_chart/skeleton_loader.vue';
import DatetimeRangePicker from '~/observability/components/datetime_range_picker.vue';
import {
  activeSessionHistoryQueries,
  activeSessionHistorySummary,
  activeSessionHistoryTimelines,
} from '../mock_data';

const at = (time) => new Date(`2026-10-15T${time}:00Z`).getTime();
const hourly = (loads) =>
  loads.map((load, hour) => ({
    bucket_start: `2026-10-15T0${7 + hour}:00:00Z`,
    source: 'rollup_1h',
    avg_aas: load,
    peak_aas: null,
    p99_aas: null,
  }));
// Intl puts thin spaces around the dash of a range.
const normalized = (text) => text.replace(/\s+/g, ' ');

describe('ActiveSessionHistoryApp component', () => {
  let wrapper;
  let mockAxios;

  useFakeDate(2026, 9, 15, 10, 0);

  const summaryUrl = '/admin/database_diagnostics/active_session_history.json';
  const timelineUrl = '/admin/database_diagnostics/active_session_history_timeline.json';

  const requestsTo = (url) => mockAxios.history.get.filter((request) => request.url === url);
  const findSkeletonLoader = () => wrapper.findComponent(GlSkeletonLoader);
  const findErrorAlert = () => wrapper.findByTestId('error-alert');
  const findPanel = () => wrapper.findComponent(GlDashboardPanel);
  const findChart = () => wrapper.findComponent(ActiveSessionHistoryChart);
  const loadsAt = (time) =>
    findChart()
      .props('series')
      .map(({ name, data }) => [
        name,
        data.find(([start]) => new Date(start).getTime() === at(time))[1],
      ]);
  const findWaitEventTypeRows = () =>
    wrapper.findAll('[data-testid="wait-event-types-table"] tbody tr');
  const findTopQueries = () => wrapper.findComponentByTestId('top-queries');
  const findDateRangeListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findDatetimeRangePicker = () => wrapper.findComponent(DatetimeRangePicker);
  const findTimeRangeGroup = () => wrapper.findComponent(GlFormGroup);
  const dateRangeLimits = 'A time range can be up to 24 hours long, and start up to 30 days ago.';
  const loadPerMinuteHelp =
    'Average active sessions per minute, stacked by wait event type. An average of 1 means one session was running or waiting for the whole minute, or two sessions for half of it.';

  const selectDateRange = async (value) => {
    findDateRangeListbox().vm.$emit('select', value);
    await waitForPromises();
  };
  const pickCustomDateRange = async (startDate, endDate) => {
    await selectDateRange('custom');
    findDatetimeRangePicker().vm.$emit('input', {
      startDate: new Date(startDate),
      endDate: new Date(endDate),
    });
    await waitForPromises();
  };
  const mockTimelines = (timelines = activeSessionHistoryTimelines) => {
    mockAxios.onGet(timelineUrl).reply(({ params }) => [
      HTTP_STATUS_OK,
      {
        installed: true,
        window: activeSessionHistorySummary.window,
        timelines: Object.fromEntries(
          params.wait_event_types.map((type) => [type, timelines[type]]),
        ),
      },
    ]);
  };

  const createComponent = async ({ summary = activeSessionHistorySummary } = {}) => {
    mockAxios.onGet(summaryUrl).replyOnce(HTTP_STATUS_OK, summary);
    wrapper = mountExtended(ActiveSessionHistoryApp, {
      stubs: { ActiveSessionHistoryChart: true },
    });
    await waitForPromises();
  };

  beforeEach(() => {
    mockAxios = new MockAdapter(axios);
    mockTimelines();
  });

  afterEach(() => {
    mockAxios.restore();
  });

  describe('when opened', () => {
    it('shows a skeleton loader until the summary loads', async () => {
      mockAxios.onGet(summaryUrl).reply(() => new Promise(() => {}));
      wrapper = mountExtended(ActiveSessionHistoryApp);
      await nextTick();

      expect(findSkeletonLoader().exists()).toBe(true);
    });

    it('reads the last hour', async () => {
      await createComponent();

      expect(requestsTo(summaryUrl).map(({ params }) => params)).toEqual([
        { from: '2026-10-15T09:00:00.000Z', to: '2026-10-15T10:00:00.000Z' },
      ]);
    });
  });

  describe('when pg_ash is not installed', () => {
    beforeEach(async () => {
      await createComponent({ summary: { installed: false } });
    });

    it('links to the install instructions and reads no timeline', () => {
      const message = wrapper.findByTestId('not-installed');

      expect(message.text()).toBe('pg_ash is not installed. How do I install it?');
      expect(message.find('a').attributes('href')).toBe(
        '/help/administration/monitoring/performance/_index.md#active-session-history',
      );
      expect(requestsTo(timelineUrl)).toHaveLength(0);
    });
  });

  describe('when another pg_ash version is installed', () => {
    beforeEach(async () => {
      await createComponent({
        summary: {
          installed: true,
          supported: false,
          installed_version: '1.5',
          supported_version: '2.0-beta1',
        },
      });
    });

    it('names both versions and links to the install instructions instead of reading', () => {
      const message = wrapper.findByTestId('unsupported-version');

      expect(message.text()).toBe(
        'pg_ash 1.5 is installed, but this version of GitLab needs 2.0-beta1. How do I reinstall it?',
      );
      expect(message.find('a').attributes('href')).toBe(
        '/help/administration/monitoring/performance/_index.md#active-session-history',
      );
      expect(wrapper.findByTestId('time-range').exists()).toBe(false);
      expect(requestsTo(timelineUrl)).toHaveLength(0);
    });
  });

  describe.each`
    description                              | reply
    ${'fails to load'}                       | ${[HTTP_STATUS_INTERNAL_SERVER_ERROR]}
    ${'is not JSON, such as a sign-in page'} | ${[HTTP_STATUS_OK, '<!DOCTYPE html><html></html>']}
  `('when the summary $description', ({ reply }) => {
    beforeEach(async () => {
      mockAxios.onGet(summaryUrl).replyOnce(...reply);
      wrapper = mountExtended(ActiveSessionHistoryApp);
      await waitForPromises();
    });

    it('shows an error alert instead of a pg_ash state', () => {
      expect(findErrorAlert().text()).toContain(
        'Failed to load active session history. Try again.',
      );
      expect(wrapper.findByTestId('not-installed').exists()).toBe(false);
    });

    it('reads again from the alert', async () => {
      mockAxios.onGet(summaryUrl).replyOnce(HTTP_STATUS_OK, activeSessionHistorySummary);
      findErrorAlert().find('button').trigger('click');
      await waitForPromises();

      expect(findErrorAlert().exists()).toBe(false);
      expect(findWaitEventTypeRows()).toHaveLength(2);
    });
  });

  describe('when admin mode is inactive', () => {
    beforeEach(async () => {
      mockAxios.onGet(summaryUrl).replyOnce(HTTP_STATUS_UNAUTHORIZED, {
        message: 'Admin mode is inactive. Please re-authenticate.',
      });
      wrapper = mountExtended(ActiveSessionHistoryApp);
      await waitForPromises();
    });

    it('says so, instead of suggesting that trying again helps', () => {
      expect(findErrorAlert().text()).toContain('Admin mode is inactive. Please re-authenticate.');
      expect(findErrorAlert().text()).not.toContain('Failed to load');
    });
  });

  describe('when the summary loads', () => {
    beforeEach(async () => {
      await createComponent();
    });

    it('explains the load per minute', () => {
      expect(normalized(findPanel().text())).toContain(loadPerMinuteHelp);
    });

    it('titles the chart panel with a heading and the time range', () => {
      expect(wrapper.findByRole('heading', { level: 2, name: 'Database load' }).exists()).toBe(
        true,
      );
      expect(normalized(findPanel().props('subtitle'))).toBe('Oct 15, 2026, 8:58 – 9:59 AM GMT');
    });

    it('shows the wait event types and the top queries in tabs', () => {
      expect(wrapper.findAll('[role="tab"]').wrappers.map((tab) => tab.text())).toEqual([
        'Wait event types',
        'Top queries',
      ]);
      expect(
        findWaitEventTypeRows().wrappers.map((row) =>
          row.findAll('td').wrappers.map((cell) => cell.text()),
        ),
      ).toEqual([
        ['Lock', '62.5%', '3.95', '4.00'],
        ['CPU*', '37.5%', '0.00', 'Not available'],
      ]);
      expect(findTopQueries().props('queries')).toEqual(activeSessionHistoryQueries);
    });

    it('names both tables', async () => {
      expect(wrapper.findByRole('table', { name: 'Wait event types' }).exists()).toBe(true);

      await wrapper.findByRole('tab', { name: 'Top queries' }).trigger('click');

      expect(wrapper.findByRole('table', { name: 'Top queries' }).exists()).toBe(true);
    });

    it('does not warn about sampling or missing query text', () => {
      expect(wrapper.findByTestId('sampling-off-alert').exists()).toBe(false);
      expect(wrapper.findByTestId('query-text-help').exists()).toBe(false);
    });

    it('reads the timelines of all wait event types in one request over the same window', () => {
      expect(requestsTo(timelineUrl).map(({ params }) => params)).toEqual([
        {
          wait_event_types: ['Lock', 'CPU*'],
          from: '2026-10-15T08:58:00Z',
          to: '2026-10-15T09:59:00Z',
        },
      ]);
    });

    it('charts each wait event type, with no load in a minute without samples', () => {
      expect(findChart().props('hourly')).toBe(false);
      expect(loadsAt('09:10')).toEqual([
        ['Lock', 4],
        ['CPU*', 0.5],
      ]);
      expect(loadsAt('09:30')).toEqual([
        ['Lock', 0],
        ['CPU*', 0],
      ]);
      expect(loadsAt('09:40')).toEqual([
        ['Lock', 0],
        ['CPU*', 0.5],
      ]);
    });
  });

  describe('while the timelines load', () => {
    beforeEach(async () => {
      mockAxios.onGet(timelineUrl).reply(() => new Promise(() => {}));
      await createComponent();
    });

    it('shows the time range, with a chart skeleton in the panel', () => {
      expect(normalized(findPanel().text())).toContain('Oct 15, 2026, 8:58 – 9:59 AM GMT');
      expect(findPanel().findComponent(ChartSkeletonLoader).exists()).toBe(true);
      expect(findChart().exists()).toBe(false);
    });

    it('explains the load per minute', () => {
      expect(normalized(findPanel().text())).toContain(loadPerMinuteHelp);
    });
  });

  const mixedTimelines = {
    installed: true,
    timelines: { Lock: hourly([2, 2, null]), 'CPU*': activeSessionHistoryTimelines['CPU*'] },
  };
  const partialTimelines = {
    installed: true,
    timelines: { Lock: activeSessionHistoryTimelines.Lock },
  };

  describe.each`
    description                                  | reply
    ${'fail to load'}                            | ${[HTTP_STATUS_INTERNAL_SERVER_ERROR]}
    ${'are not JSON, such as a sign-in page'}    | ${[HTTP_STATUS_OK, '<!DOCTYPE html><html></html>']}
    ${'say pg_ash was removed'}                  | ${[HTTP_STATUS_OK, { installed: false }]}
    ${'say pg_ash changed version'}              | ${[HTTP_STATUS_OK, { installed: true, supported: false }]}
    ${'give wait event types different buckets'} | ${[HTTP_STATUS_OK, mixedTimelines]}
    ${'leave out a wait event type'}             | ${[HTTP_STATUS_OK, partialTimelines]}
  `('when the timelines $description', ({ reply }) => {
    beforeEach(async () => {
      mockAxios.resetHandlers();
      mockAxios.onGet(timelineUrl).replyOnce(...reply);
      mockTimelines();
      await createComponent();
    });

    it('announces an error in the panel that retries', async () => {
      const error = wrapper.findByTestId('timelines-error');

      expect(error.text()).toContain('Failed to load the chart. Try again.');
      expect(error.attributes('role')).toBe('alert');

      error.findByRole('button', { name: 'Retry' }).trigger('click');
      await waitForPromises();

      expect(findChart().exists()).toBe(true);
    });
  });

  describe('when pg_ash reads hourly summaries for the time range', () => {
    beforeEach(async () => {
      // The current hour has no summary yet.
      mockTimelines({ Lock: hourly([2, 2, null]), 'CPU*': hourly([1, null, null]) });
      await createComponent();
    });

    it('charts the hours', () => {
      expect(findChart().props('hourly')).toBe(true);
      expect(findChart().props('series')[0].data).toHaveLength(3);
    });

    it('explains the load per hour', () => {
      expect(normalized(findPanel().text())).toContain(
        'Average active sessions per hour, stacked by wait event type. An average of 1 means one session was running or waiting for the whole hour, or two sessions for half of it.',
      );
    });

    it('leaves an hour without samples empty, and charts no load for a wait event type missing from a sampled hour', () => {
      expect(
        findChart()
          .props('series')
          .map(({ data }) => data.map(([, load]) => load)),
      ).toEqual([
        [2, 2, null],
        [1, 0, null],
      ]);
    });
  });

  const earlierTimelines = {
    installed: true,
    window: {},
    timelines: {
      Lock: activeSessionHistoryTimelines.Lock.map((bucket) => ({ ...bucket, avg_aas: 9 })),
      'CPU*': activeSessionHistoryTimelines['CPU*'],
    },
  };

  describe.each`
    description   | lateReply
    ${'results'}  | ${[HTTP_STATUS_OK, earlierTimelines]}
    ${'failures'} | ${[HTTP_STATUS_INTERNAL_SERVER_ERROR]}
  `('when the timeline $description of an earlier time range arrive late', ({ lateReply }) => {
    beforeEach(async () => {
      const settlers = [];
      mockAxios.resetHandlers();
      mockAxios.onGet(timelineUrl).replyOnce(
        () =>
          new Promise((resolve) => {
            settlers.push(resolve);
          }),
      );
      mockTimelines();
      await createComponent();

      mockAxios.onGet(summaryUrl).replyOnce(HTTP_STATUS_OK, activeSessionHistorySummary);
      await selectDateRange('4h');

      settlers.forEach((settle) => settle(lateReply));
      await waitForPromises();
    });

    it('stops waiting for the timelines of the earlier time range', () => {
      expect(requestsTo(timelineUrl).map(({ signal }) => signal.aborted)).toEqual([true, false]);
    });

    it('keeps the timelines of the latest time range', () => {
      expect(wrapper.findByTestId('timelines-error').exists()).toBe(false);
      expect(loadsAt('09:10')).toEqual([
        ['Lock', 4],
        ['CPU*', 0.5],
      ]);
    });
  });

  describe('when sampling is off', () => {
    beforeEach(async () => {
      await createComponent({
        summary: { ...activeSessionHistorySummary, sampling_enabled: false },
      });
    });

    it('links to the sampling setting', () => {
      const alert = wrapper.findByTestId('sampling-off-alert');

      expect(alert.text()).toBe(
        'Session sampling is off, so new database activity is not recorded. Turn on session sampling.',
      );
      expect(alert.find('a').attributes('href')).toBe(
        '/admin/application_settings/metrics_and_profiling#js-pg-ash-settings',
      );
    });
  });

  describe('when there are no samples in the time range', () => {
    beforeEach(async () => {
      await createComponent({
        summary: {
          ...activeSessionHistorySummary,
          coverage: null,
          wait_event_types: [],
          top_queries: [],
        },
      });
    });

    it('says so for the time range it read, instead of showing the chart and tables', () => {
      expect(normalized(wrapper.findByTestId('time-range').text())).toBe(
        'Time range: Oct 15, 2026, 8:58 – 9:59 AM GMT',
      );
      expect(wrapper.findByTestId('no-samples').text()).toBe('No samples in this time range.');
      expect(findPanel().exists()).toBe(false);
      expect(findTopQueries().exists()).toBe(false);
      expect(requestsTo(timelineUrl)).toHaveLength(0);
    });
  });

  describe('when only the unattributed load is in the top queries', () => {
    beforeEach(async () => {
      await createComponent({
        summary: {
          ...activeSessionHistorySummary,
          top_queries: activeSessionHistoryQueries.filter(
            ({ query_id: queryId }) => queryId === null,
          ),
        },
      });
    });

    it('does not mention query text', () => {
      expect(wrapper.findByTestId('query-text-help').exists()).toBe(false);
    });
  });

  describe('when no top query has text', () => {
    beforeEach(async () => {
      await createComponent({
        summary: {
          ...activeSessionHistorySummary,
          top_queries: activeSessionHistoryQueries.map((query) => ({ ...query, query_text: null })),
        },
      });
    });

    it('explains where query text comes from', () => {
      const help = wrapper.findByTestId('query-text-help');

      expect(help.text()).toBe(
        'Query text comes from pg_stat_statements, and none was found for these queries. How do I get query text?',
      );
      expect(help.find('a').attributes('href')).toBe(
        '/help/administration/monitoring/performance/_index.md#query-ids-and-text',
      );
    });
  });

  describe('time range', () => {
    beforeEach(async () => {
      await createComponent();
      mockAxios.onGet(summaryUrl).reply(HTTP_STATUS_OK, activeSessionHistorySummary);
    });

    it('offers the last 1, 4, 12 and 24 hours, and a custom range, under a label', () => {
      expect(
        findDateRangeListbox()
          .props('items')
          .map(({ value }) => value),
      ).toEqual(['1h', '4h', '12h', '24h', 'custom']);
      expect(findDateRangeListbox().props('selected')).toBe('1h');
      expect(findTimeRangeGroup().find('legend, label').text()).toBe('Time range');
      expect(findDatetimeRangePicker().exists()).toBe(false);
      expect(wrapper.findByText(dateRangeLimits).exists()).toBe(false);
    });

    it('reads a chosen preset right away, counting back from now', async () => {
      await selectDateRange('12h');

      expect(requestsTo(summaryUrl).at(-1).params).toEqual({
        from: '2026-10-14T22:00:00.000Z',
        to: '2026-10-15T10:00:00.000Z',
      });
    });

    describe('when a custom range is chosen', () => {
      beforeEach(async () => {
        await selectDateRange('custom');
      });

      it('opens the picker for starts from 30 days back to today, across midnight', () => {
        expect(findDatetimeRangePicker().props()).toMatchObject({
          startOpened: true,
          defaultMinDate: new Date('2026-09-15T10:00:00Z'),
          maxDateRange: 2,
        });
        expect(wrapper.findAllComponents(GlDatepicker).at(0).props('maxDate')).toEqual(
          new Date('2026-10-15T10:00:00Z'),
        );
      });

      it('states the limits', () => {
        expect(wrapper.findByText(dateRangeLimits).exists()).toBe(true);
      });

      it('waits for both dates without an error or a read', () => {
        expect(findTimeRangeGroup().attributes('aria-invalid')).toBeUndefined();
        expect(findErrorAlert().exists()).toBe(false);
        expect(findWaitEventTypeRows()).toHaveLength(2);
        expect(requestsTo(summaryUrl)).toHaveLength(1);
      });

      it('hides the picker when a preset is chosen again', async () => {
        await selectDateRange('4h');

        expect(findDatetimeRangePicker().exists()).toBe(false);
      });
    });

    it('reads the custom time range again when Custom is chosen after a preset', async () => {
      await pickCustomDateRange('2026-10-14T13:00:00Z', '2026-10-14T15:30:00Z');
      await selectDateRange('4h');
      await selectDateRange('custom');

      expect(requestsTo(summaryUrl).at(-1).params).toEqual({
        from: '2026-10-14T13:00:00.000Z',
        to: '2026-10-14T15:30:00.000Z',
      });
    });

    it('stays on the chosen table when another time range loads', async () => {
      await wrapper.findAll('[role="tab"]').at(1).trigger('click');
      await selectDateRange('4h');

      expect(wrapper.find('[role="tab"][aria-selected="true"]').text()).toBe('Top queries');
    });

    it.each`
      description                                        | startDate                 | endDate
      ${'a custom time range'}                           | ${'2026-10-14T13:00:00Z'} | ${'2026-10-14T15:30:00Z'}
      ${'a 61-minute range just after the 30-day limit'} | ${'2026-09-15T10:01:00Z'} | ${'2026-09-15T11:02:00Z'}
    `('reads $description once both dates are picked', async ({ startDate, endDate }) => {
      await pickCustomDateRange(startDate, endDate);

      expect(findTimeRangeGroup().attributes('aria-invalid')).toBeUndefined();
      expect(requestsTo(summaryUrl).at(-1).params).toEqual({
        from: new Date(startDate).toISOString(),
        to: new Date(endDate).toISOString(),
      });
    });

    describe.each`
      description                                         | startDate                 | endDate                   | message
      ${'over 24 hours'}                                  | ${'2026-10-13T09:00:00Z'} | ${'2026-10-14T09:01:00Z'} | ${'Choose a time range of up to 24 hours.'}
      ${'starting in the future'}                         | ${'2026-10-15T11:00:00Z'} | ${'2026-10-15T13:00:00Z'} | ${'Choose a start in the past.'}
      ${'ending before it starts'}                        | ${'2026-10-14T15:00:00Z'} | ${'2026-10-14T13:00:00Z'} | ${'Choose an end after the start.'}
      ${'ending when it starts'}                          | ${'2026-10-14T13:00:10Z'} | ${'2026-10-14T13:00:10Z'} | ${'Choose an end after the start.'}
      ${'within one minute'}                              | ${'2026-10-14T13:00:10Z'} | ${'2026-10-14T13:00:50Z'} | ${'Choose an end at least one minute after the start.'}
      ${'starting over 30 days back'}                     | ${'2026-09-15T09:00:00Z'} | ${'2026-09-15T11:00:00Z'} | ${'Choose a start within the last 30 days.'}
      ${'shorter than 61 minutes, near the 30-day limit'} | ${'2026-09-15T10:20:00Z'} | ${'2026-09-15T10:40:00Z'} | ${'A time range shorter than 61 minutes is read as the 61 minutes before its end, which would start over 30 days ago. Choose a later end.'}
    `('with a custom time range $description', ({ startDate, endDate, message }) => {
      beforeEach(async () => {
        await pickCustomDateRange(startDate, endDate);
      });

      it('says what to change instead of reading it', () => {
        expect(wrapper.findByText(message).exists()).toBe(true);
        expect(findTimeRangeGroup().attributes('aria-invalid')).toBe('true');
        expect(findDatetimeRangePicker().props('state')).toBe(false);
        expect(requestsTo(summaryUrl)).toHaveLength(1);
      });
    });

    it('shows the period pg_ash read when it differs from the window', async () => {
      mockAxios.onGet(summaryUrl).reply(HTTP_STATUS_OK, {
        ...activeSessionHistorySummary,
        window: { from: '2026-10-14T09:59:00Z', to: '2026-10-15T09:59:00Z' },
        coverage: { from: '2026-10-14T09:00:00Z', to: '2026-10-15T10:00:00Z', source: 'rollup_1h' },
      });
      await selectDateRange('24h');

      expect(normalized(findPanel().props('subtitle'))).toBe(
        'Oct 14, 2026, 9:00 AM GMT – Oct 15, 2026, 10:00 AM GMT',
      );
    });
  });

  describe('in a time zone whose clocks changed in the last 30 days', () => {
    useFakeDate(2026, 10, 10, 10, 0);

    beforeEach(async () => {
      timezoneMock.register('US/Eastern');
      await createComponent();
    });

    afterEach(() => {
      timezoneMock.unregister();
    });

    it('rejects starts over 30 days back in UTC, as the server does', async () => {
      await pickCustomDateRange('2026-10-11T09:30:00Z', '2026-10-11T11:00:00Z');

      expect(wrapper.findByText('Choose a start within the last 30 days.').exists()).toBe(true);
      expect(requestsTo(summaryUrl)).toHaveLength(1);
    });
  });

  describe('as time passes while the tab is open', () => {
    beforeEach(() => {
      jest.useFakeTimers({ legacyFakeTimers: false });
      jest.setSystemTime(new Date('2026-10-15T10:00:00Z'));
    });

    afterEach(() => {
      jest.useFakeTimers({ legacyFakeTimers: true });
    });

    it('counts the 30 days back from when Custom is chosen', async () => {
      mockAxios.onGet(summaryUrl).reply(HTTP_STATUS_OK, activeSessionHistorySummary);
      wrapper = mountExtended(ActiveSessionHistoryApp, {
        stubs: { ActiveSessionHistoryChart: true },
      });

      jest.setSystemTime(new Date('2026-10-16T09:00:00Z'));
      findDateRangeListbox().vm.$emit('select', 'custom');
      await nextTick();

      expect(findDatetimeRangePicker().props('defaultMinDate')).toEqual(
        new Date('2026-09-16T09:00:00Z'),
      );

      await waitForPromises();
    });

    it('checks a picked range against the time it is picked', async () => {
      mockAxios.onGet(summaryUrl).reply(HTTP_STATUS_OK, activeSessionHistorySummary);
      wrapper = mountExtended(ActiveSessionHistoryApp, {
        stubs: { ActiveSessionHistoryChart: true },
      });
      findDateRangeListbox().vm.$emit('select', 'custom');
      await nextTick();

      jest.setSystemTime(new Date('2026-10-15T10:05:00Z'));
      findDatetimeRangePicker().vm.$emit('input', {
        startDate: new Date('2026-10-15T10:02:00Z'),
        endDate: new Date('2026-10-15T10:04:00Z'),
      });
      await waitForPromises();

      expect(requestsTo(summaryUrl).at(-1).params).toEqual({
        from: '2026-10-15T10:02:00.000Z',
        to: '2026-10-15T10:04:00.000Z',
      });
    });
  });

  describe('when the time range changes while a read runs', () => {
    let settleFirst;

    beforeEach(async () => {
      mockAxios.onGet(summaryUrl).replyOnce(
        () =>
          new Promise((resolve) => {
            settleFirst = resolve;
          }),
      );
      wrapper = mountExtended(ActiveSessionHistoryApp, {
        stubs: { ActiveSessionHistoryChart: true },
      });
      await nextTick();
    });

    it.each`
      description           | firstReply
      ${'an older result'}  | ${[HTTP_STATUS_OK, { installed: false }]}
      ${'an older failure'} | ${[HTTP_STATUS_INTERNAL_SERVER_ERROR]}
    `('keeps the latest result over $description that arrives later', async ({ firstReply }) => {
      mockAxios.onGet(summaryUrl).replyOnce(HTTP_STATUS_OK, activeSessionHistorySummary);
      await selectDateRange('4h');

      settleFirst(firstReply);
      await waitForPromises();

      expect(wrapper.findByTestId('not-installed').exists()).toBe(false);
      expect(findErrorAlert().exists()).toBe(false);
      expect(findPanel().exists()).toBe(true);
    });

    it('keeps loading until the latest read settles, even when an older one settles first', async () => {
      mockAxios.onGet(summaryUrl).replyOnce(() => new Promise(() => {}));
      await selectDateRange('4h');

      settleFirst([HTTP_STATUS_OK, activeSessionHistorySummary]);
      await waitForPromises();

      expect(findSkeletonLoader().exists()).toBe(true);
      expect(findPanel().exists()).toBe(false);
    });

    it('stops waiting for the earlier read', async () => {
      mockAxios.onGet(summaryUrl).replyOnce(HTTP_STATUS_OK, activeSessionHistorySummary);
      await selectDateRange('4h');

      expect(requestsTo(summaryUrl).map(({ signal }) => signal.aborted)).toEqual([true, false]);
    });

    it('stops waiting for its read when the tab closes', () => {
      wrapper.destroy();

      expect(requestsTo(summaryUrl)[0].signal.aborted).toBe(true);
    });

    it('starts no chart reads when the tab closes first', async () => {
      wrapper.destroy();
      settleFirst([HTTP_STATUS_OK, activeSessionHistorySummary]);
      await waitForPromises();

      expect(requestsTo(timelineUrl)).toHaveLength(0);
    });
  });
});
