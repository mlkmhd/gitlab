import { shallowMount } from '@vue/test-utils';
import FreeTrialBillingWithDapMonthlyCommitApp from 'ee/groups/billing/components/app_with_dap_monthly_commit.vue';
import CurrentPlanCard from 'ee/groups/billing/components/components_with_dap_monthly_commit/current_plan_card.vue';
import DapMonthlyCreditCard from 'ee/groups/billing/components/components_with_dap_monthly_commit/dap_monthly_credit_card.vue';
import PostTrialUsageCard from 'ee/groups/billing/components/components_with_dap_monthly_commit/post_trial_usage_card.vue';
import ReTrialCard from 'ee/groups/billing/components/components_with_dap_monthly_commit/re_trial_card.vue';

describe('FreeTrialBillingWithDapMonthlyCommitApp', () => {
  let wrapper;

  const findCurrentPlanCard = () => wrapper.findComponent(CurrentPlanCard);
  const findDapMonthlyCreditCard = () => wrapper.findComponent(DapMonthlyCreditCard);
  const findReTrialCard = () => wrapper.findComponent(ReTrialCard);
  const findPostTrialUsageCard = () => wrapper.findComponent(PostTrialUsageCard);

  const postTrialUsage = { seatsUsed: 6, calloutFeatureName: 'post_trial_usage_card' };

  const createComponent = ({ provide = {} } = {}) => {
    wrapper = shallowMount(FreeTrialBillingWithDapMonthlyCommitApp, { provide });
  };

  it('renders current plan and credit card components', () => {
    createComponent();

    expect(findCurrentPlanCard().exists()).toBe(true);
    expect(findDapMonthlyCreditCard().exists()).toBe(true);
  });

  it('renders the re-trial card above the plan cards', () => {
    createComponent();

    expect(findReTrialCard().exists()).toBe(true);

    const inDocumentOrder = Array.from(wrapper.element.querySelectorAll('*'));

    expect(inDocumentOrder.indexOf(findReTrialCard().element)).toBeLessThan(
      inDocumentOrder.indexOf(findCurrentPlanCard().element),
    );
  });

  it('renders the post-trial usage card above the re-trial card', () => {
    createComponent({ provide: { postTrialUsage } });

    expect(findPostTrialUsageCard().props('usage')).toEqual(postTrialUsage);

    const inDocumentOrder = Array.from(wrapper.element.querySelectorAll('*'));

    expect(inDocumentOrder.indexOf(findPostTrialUsageCard().element)).toBeLessThan(
      inDocumentOrder.indexOf(findReTrialCard().element),
    );
  });

  it('does not render the post-trial usage card without trial usage', () => {
    createComponent();

    expect(findPostTrialUsageCard().exists()).toBe(false);
  });
});
