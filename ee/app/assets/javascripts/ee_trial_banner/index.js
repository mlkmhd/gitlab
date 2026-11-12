export default async function initEETrialBanner() {
  const trialBanner = document.querySelector('.js-gitlab-ee-license-banner');

  if (!trialBanner) {
    return;
  }

  const { default: EETrialBanner } = await import(
    /* webpackChunkName: 'eeTrialBanner' */ './ee_trial_banner'
  );

  new EETrialBanner(trialBanner).init();
}
