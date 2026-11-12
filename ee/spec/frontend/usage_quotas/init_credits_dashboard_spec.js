import { initCreditsDashboard } from 'ee/usage_quotas/init_credits_dashboard';
import { initGitlabCreditsDashboard } from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/index';
import { initUsageBillingDashboard } from 'ee/usage_quotas/usage_billing/index';

jest.mock('ee/usage_quotas/wallet_agnostic_credits_dashboard/index', () => ({
  initGitlabCreditsDashboard: jest.fn(),
}));
jest.mock('ee/usage_quotas/usage_billing/index', () => ({
  initUsageBillingDashboard: jest.fn(),
}));

describe('initCreditsDashboard', () => {
  const createElement = (dataset = {}) => {
    const el = document.createElement('div');
    Object.assign(el.dataset, dataset);
    return el;
  };

  describe('when isFree is "true"', () => {
    it('initializes the usage billing dashboard', () => {
      const el = createElement({ isFree: 'true' });

      initCreditsDashboard(el);

      expect(initUsageBillingDashboard).toHaveBeenCalledWith(el);
      expect(initGitlabCreditsDashboard).not.toHaveBeenCalled();
    });
  });

  describe.each(['false', undefined])('when isFree is %s', (isFree) => {
    it('initializes the GitLab Credits dashboard', () => {
      const el = createElement(isFree === undefined ? {} : { isFree });

      initCreditsDashboard(el);

      expect(initGitlabCreditsDashboard).toHaveBeenCalledWith(el);
      expect(initUsageBillingDashboard).not.toHaveBeenCalled();
    });
  });

  describe('when the element is missing', () => {
    it('passes null to the GitLab Credits dashboard', () => {
      initCreditsDashboard(null);

      expect(initGitlabCreditsDashboard).toHaveBeenCalledWith(null);
      expect(initUsageBillingDashboard).not.toHaveBeenCalled();
    });
  });
});
