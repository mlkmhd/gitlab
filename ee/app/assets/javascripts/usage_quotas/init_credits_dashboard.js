import { parseBoolean } from '@gitlab/frontend-utils';
import { initGitlabCreditsDashboard } from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/index';
import { initUsageBillingDashboard } from 'ee/usage_quotas/usage_billing/index';

/**
 * @param {HTMLElement} el
 */
export function initCreditsDashboard(el) {
  const isFree = parseBoolean(el?.dataset?.isFree);

  if (!isFree) {
    return initGitlabCreditsDashboard(el);
  }

  return initUsageBillingDashboard(el);
}
