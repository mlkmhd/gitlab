import waitForPromises from 'helpers/wait_for_promises';

const mockLoadFindAndReplace = jest.fn();

jest.mock('~/behaviors/autosize', () => ({}));
jest.mock('~/behaviors/collapse_sidebar_on_window_resize', () => jest.fn());
jest.mock('~/behaviors/copy_to_clipboard', () => jest.fn());
jest.mock('~/behaviors/gl_emoji', () => jest.fn());
jest.mock('~/behaviors/markdown/copy_as_gfm', () => jest.fn());
jest.mock('~/behaviors/quick_submit', () => ({ initQuickSubmit: jest.fn() }));
jest.mock('~/behaviors/toasts', () => ({ initToastMessages: jest.fn() }));
jest.mock('~/behaviors/global_alerts', () => ({ initGlobalAlerts: jest.fn() }));
jest.mock('~/behaviors/shortcuts', () => ({}));
jest.mock('~/behaviors/toggler_behavior', () => ({}));
jest.mock('~/behaviors/preview_markdown', () => ({}));
jest.mock('~/behaviors/configure_path_helpers', () => ({}));
jest.mock('~/behaviors/find_and_replace', () => {
  mockLoadFindAndReplace();
  return {};
});

describe('global behaviors', () => {
  beforeEach(() => {
    jest.resetModules();
    jest.spyOn(window, 'requestIdleCallback').mockImplementation(() => {});
  });

  it.each`
    features                     | loadsFindAndReplace
    ${{ findAndReplace: true }}  | ${true}
    ${{ findAndReplace: false }} | ${false}
    ${{}}                        | ${false}
    ${undefined}                 | ${false}
  `(
    'loads find-and-replace: $loadsFindAndReplace with features $features',
    async ({ features, loadsFindAndReplace }) => {
      gon.features = features;

      // eslint-disable-next-line global-require
      require('~/behaviors');
      await waitForPromises();

      expect(mockLoadFindAndReplace).toHaveBeenCalledTimes(loadsFindAndReplace ? 1 : 0);
    },
  );
});
