import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import initEETrialBanner from 'ee/ee_trial_banner';
import EETrialBanner from 'ee/ee_trial_banner/ee_trial_banner';

jest.mock('ee/ee_trial_banner/ee_trial_banner');

describe('initEETrialBanner', () => {
  afterEach(() => {
    resetHTMLFixture();
  });

  it('does not load the banner when the page has no license banner', async () => {
    setHTMLFixture('<div></div>');

    await initEETrialBanner();

    expect(EETrialBanner).not.toHaveBeenCalled();
  });

  it('loads and initializes the banner when the page has a license banner', async () => {
    setHTMLFixture('<div class="js-gitlab-ee-license-banner"></div>');

    await initEETrialBanner();

    expect(EETrialBanner).toHaveBeenCalledWith(
      document.querySelector('.js-gitlab-ee-license-banner'),
    );
    expect(EETrialBanner.mock.instances[0].init).toHaveBeenCalled();
  });
});
