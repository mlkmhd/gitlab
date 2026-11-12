import MockAdapter from 'axios-mock-adapter';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { makeMockUserGroupCalloutDismisser } from 'helpers/mock_user_group_callout_dismisser';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_OK } from '~/lib/utils/http_status';
import UserGroupCalloutDismisser from '~/vue_shared/components/user_group_callout_dismisser.vue';
import PostTrialUsageCard from 'ee/groups/billing/components/components_with_dap_monthly_commit/post_trial_usage_card.vue';

describe('PostTrialUsageCard', () => {
  let wrapper;
  let dismissSpy;
  let mockAxios;

  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const postTrialUsage = {
    seatsUsed: 6,
    computeMinutesUsed: 375,
    creditsUsed: 40.25,
    freeSeatsLimit: 5,
    freeComputeMinutesLimit: 400,
    calloutFeatureName: 'post_trial_usage_card',
  };

  const createComponent = ({ usage = {}, shouldShowCallout = true } = {}) => {
    dismissSpy = jest.fn();

    wrapper = shallowMountExtended(PostTrialUsageCard, {
      propsData: {
        usage: { ...postTrialUsage, ...usage },
      },
      provide: {
        groupId: 7,
        upgradeToPremiumUrl: '/upgrade/premium',
        upgradeToPremiumTrackingUrl: '/track/premium',
      },
      stubs: {
        UserGroupCalloutDismisser: makeMockUserGroupCalloutDismisser({
          dismiss: dismissSpy,
          shouldShowCallout,
        }),
      },
    });
  };

  const findCard = () => wrapper.findByTestId('post-trial-usage-card');
  const findCta = () => wrapper.findComponentByTestId('post-trial-usage-card-cta');
  const findDismissButton = () => wrapper.findComponentByTestId('post-trial-usage-card-dismiss');
  const findDismisser = () => wrapper.findComponent(UserGroupCalloutDismisser);
  const findLowUsageText = () => wrapper.findByTestId('post-trial-usage-card-low-usage');
  const findMetric = (key) => wrapper.findByTestId(`post-trial-usage-metric-${key}`);
  const findMetricKeys = () =>
    wrapper
      .findAll('[data-testid^="post-trial-usage-metric-"]')
      .wrappers.map((metric) => metric.attributes('data-testid'));

  const findTrackEventSpy = () => bindInternalEventDocument(wrapper.element).trackEventSpy;

  beforeEach(() => {
    mockAxios = new MockAdapter(axios);
  });

  afterEach(() => {
    mockAxios.restore();
  });

  describe('when every metric clears its threshold', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the card', () => {
      expect(findCard().exists()).toBe(true);
    });

    it('passes the callout name and group to the dismisser', () => {
      expect(findDismisser().props()).toMatchObject({
        featureName: 'post_trial_usage_card',
        groupId: 7,
        skipQuery: true,
      });
    });

    it('renders the heading and usage message', () => {
      expect(wrapper.text()).toContain('Your GitLab Ultimate trial has ended');
      expect(wrapper.text()).toContain(
        'See how your trial usage compares to the Free plan, and upgrade to keep your team at full capacity.',
      );
      expect(findLowUsageText().exists()).toBe(false);
    });

    it('renders the metrics in order', () => {
      expect(findMetricKeys()).toEqual([
        'post-trial-usage-metric-seats',
        'post-trial-usage-metric-compute-minutes',
        'post-trial-usage-metric-credits',
      ]);
    });

    it('renders seats against the Free limit', () => {
      expect(findMetric('seats').text()).toMatchInterpolatedText('Seats 6 5 available in Free');
    });

    it('renders compute minutes against the Free limit', () => {
      expect(findMetric('compute-minutes').text()).toMatchInterpolatedText(
        'Compute minutes 375 400 available in Free',
      );
    });

    it('renders credits rounded to a whole number', () => {
      expect(findMetric('credits').text()).toMatchInterpolatedText(
        'Credits 40 Not available in Free',
      );
    });

    it('points the CTA at the Premium upgrade path', () => {
      expect(findCta().attributes('href')).toBe('/upgrade/premium');
      expect(findCta().text()).toBe('Upgrade to Premium');
    });

    it('tracks cart abandonment when the CTA is clicked', async () => {
      mockAxios.onPost('/track/premium').reply(HTTP_STATUS_OK);

      findCta().vm.$emit('click');
      await axios.waitForAll();

      expect(mockAxios.history.post).toHaveLength(1);
      expect(mockAxios.history.post[0].url).toBe('/track/premium');
    });

    it('tracks the impression once on mount with the variant and visible metrics', () => {
      const trackEventSpy = findTrackEventSpy();

      expect(trackEventSpy).toHaveBeenCalledTimes(1);
      expect(trackEventSpy).toHaveBeenCalledWith(
        'view_post_trial_usage_card_group_billing',
        { label: 'usage', property: 'seats,compute-minutes,credits' },
        undefined,
      );
    });

    it('tracks the CTA click with the variant and visible metrics', () => {
      const trackEventSpy = findTrackEventSpy();

      findCta().vm.$emit('click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'click_upgrade_on_post_trial_usage_card_group_billing',
        { label: 'usage', property: 'seats,compute-minutes,credits' },
        undefined,
      );
    });

    it('tracks the dismissal with the variant and visible metrics', () => {
      const trackEventSpy = findTrackEventSpy();

      findDismissButton().vm.$emit('click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'dismiss_post_trial_usage_card_group_billing',
        { label: 'usage', property: 'seats,compute-minutes,credits' },
        undefined,
      );
    });

    it('renders a labelled dismiss button', () => {
      expect(findDismissButton().attributes('aria-label')).toBe('Dismiss trial usage summary');
    });

    it('dismisses the callout when the dismiss button is clicked', () => {
      findDismissButton().vm.$emit('click');

      expect(dismissSpy).toHaveBeenCalled();
    });
  });

  describe.each`
    metric               | usage
    ${'seats'}           | ${{ seatsUsed: 1 }}
    ${'compute-minutes'} | ${{ computeMinutesUsed: 199 }}
    ${'credits'}         | ${{ creditsUsed: 4.9 }}
    ${'credits'}         | ${{ creditsUsed: null }}
  `('when $metric is below its threshold with $usage', ({ metric, usage }) => {
    beforeEach(() => {
      createComponent({ usage });
    });

    it('hides only that metric', () => {
      expect(findMetric(metric).exists()).toBe(false);
      expect(findMetricKeys()).toHaveLength(2);
    });

    it('leaves that metric out of the tracked visible metrics', () => {
      expect(findTrackEventSpy()).toHaveBeenCalledWith(
        'view_post_trial_usage_card_group_billing',
        {
          label: 'usage',
          property: ['seats', 'compute-minutes', 'credits']
            .filter((key) => key !== metric)
            .join(','),
        },
        undefined,
      );
    });
  });

  describe.each`
    metric               | usage
    ${'seats'}           | ${{ seatsUsed: 2 }}
    ${'compute-minutes'} | ${{ computeMinutesUsed: 200 }}
    ${'credits'}         | ${{ creditsUsed: 5 }}
  `('when $metric is exactly at its threshold with $usage', ({ metric, usage }) => {
    beforeEach(() => {
      createComponent({ usage });
    });

    it('shows that metric', () => {
      expect(findMetric(metric).exists()).toBe(true);
    });
  });

  describe('when no metric clears its threshold', () => {
    beforeEach(() => {
      createComponent({ usage: { seatsUsed: 1, computeMinutesUsed: 0, creditsUsed: null } });
    });

    it('renders the low-usage variant', () => {
      expect(findLowUsageText().text()).toBe(
        "Upgrade to a paid plan to keep access to GitLab's paid features.",
      );
      expect(findMetricKeys()).toHaveLength(0);
      expect(findCta().exists()).toBe(true);
    });

    it('tracks the impression as the low-usage variant with no visible metrics', () => {
      expect(findTrackEventSpy()).toHaveBeenCalledWith(
        'view_post_trial_usage_card_group_billing',
        { label: 'low_usage', property: '' },
        undefined,
      );
    });
  });

  describe('when the callout was dismissed in this session', () => {
    beforeEach(() => {
      createComponent({ shouldShowCallout: false });
    });

    it('does not render the card', () => {
      expect(findCard().exists()).toBe(false);
    });

    it('does not track the impression', () => {
      expect(findTrackEventSpy()).not.toHaveBeenCalled();
    });
  });
});
