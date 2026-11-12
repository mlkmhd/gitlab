import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { parseBoolean } from '@gitlab/frontend-utils';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import createApolloClient from '~/lib/graphql';
import FreeTierTrialApp from 'ee/usage_quotas/usage_billing/components/free_tier_trial_app.vue';
import { usageBillingCacheConfig } from './apollo_cache_config';

/**
 * @param {HTMLElement} el
 */
export function initUsageBillingDashboard(el) {
  if (!el) {
    return null;
  }

  const {
    namespacePath,
    organizationId,
    upgradeButtonPath,
    purchaseCreditsPath,
    creditsGeneralizationUi,
  } = el.dataset;

  Vue.use(VueApollo);
  const apolloProvider = new VueApollo({
    defaultClient: createApolloClient({}, { cacheConfig: usageBillingCacheConfig }),
  });

  return initVueApp({
    el,
    name: 'UsageBillingDashboardRoot',
    apolloProvider,
    provide: {
      namespacePath,
      organizationId,
      upgradeButtonPath,
      purchaseCreditsPath,
      creditsGeneralizationUi: parseBoolean(creditsGeneralizationUi),
    },
    component: FreeTierTrialApp,
  });
}
