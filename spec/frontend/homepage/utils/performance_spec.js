import { markHomepageAppMounted, markHomepageWidgetLoaded } from '~/homepage/utils/performance';

describe('homepage performance utils', () => {
  let marks;

  beforeEach(() => {
    marks = new Set();
    jest.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => cb());
    window.performance.mark = jest.fn((name) => marks.add(name));
    window.performance.measure = jest.fn();
    window.performance.getEntriesByName = jest.fn((name) => (marks.has(name) ? [{ name }] : []));
  });

  describe('markHomepageAppMounted', () => {
    it('sets the app mounted mark', () => {
      markHomepageAppMounted();

      expect(window.performance.mark).toHaveBeenCalledWith('homepage-app-mounted');
    });
  });

  describe('when the tab is hidden', () => {
    beforeEach(() => {
      jest.spyOn(document, 'hidden', 'get').mockReturnValue(true);
    });

    it('does not set any marks', () => {
      markHomepageAppMounted();
      markHomepageWidgetLoaded('homepage-todos-loaded');

      expect(window.performance.mark).not.toHaveBeenCalled();
    });
  });

  describe('markHomepageWidgetLoaded', () => {
    describe('when the app mount was recorded', () => {
      beforeEach(() => {
        markHomepageAppMounted();
        window.performance.mark.mockClear();
      });

      it('sets the widget mark and measures it from navigation start', () => {
        markHomepageWidgetLoaded('homepage-todos-loaded');

        expect(window.performance.mark).toHaveBeenCalledWith('homepage-todos-loaded');
        expect(window.performance.measure).toHaveBeenCalledWith(
          'homepage-todos',
          undefined,
          'homepage-todos-loaded',
        );
      });

      describe('when the tab is hidden after mount', () => {
        beforeEach(() => {
          document.dispatchEvent(new Event('visibilitychange'));
          markHomepageWidgetLoaded('homepage-todos-loaded');
        });

        it('records that the tab was hidden', () => {
          expect(window.performance.mark).toHaveBeenCalledWith('homepage-tab-hidden');
        });

        it('does not record widgets that load afterwards', () => {
          expect(window.performance.mark).not.toHaveBeenCalledWith('homepage-todos-loaded');
        });
      });

      describe('when the tab is hidden before the animation frame runs', () => {
        beforeEach(() => {
          let runFrame;
          window.requestAnimationFrame.mockImplementation((cb) => {
            runFrame = cb;
          });

          markHomepageWidgetLoaded('homepage-todos-loaded');
          document.dispatchEvent(new Event('visibilitychange'));
          runFrame();
        });

        it('does not record the widget', () => {
          expect(window.performance.mark).not.toHaveBeenCalledWith('homepage-todos-loaded');
        });
      });

      it('only records the first load of a widget', () => {
        markHomepageWidgetLoaded('homepage-todos-loaded');
        markHomepageWidgetLoaded('homepage-todos-loaded');

        expect(window.performance.mark).toHaveBeenCalledTimes(1);
        expect(window.performance.measure).toHaveBeenCalledTimes(1);
      });

      describe('when only some widgets have loaded', () => {
        beforeEach(() => {
          markHomepageWidgetLoaded('homepage-todos-loaded');
          markHomepageWidgetLoaded('homepage-merge-requests-loaded');
          markHomepageWidgetLoaded('homepage-activity-loaded');
        });

        it('does not set the widgets loaded mark', () => {
          expect(window.performance.mark).not.toHaveBeenCalledWith('homepage-widgets-loaded');
        });
      });

      describe('when all widgets have loaded', () => {
        beforeEach(() => {
          markHomepageWidgetLoaded('homepage-todos-loaded');
          markHomepageWidgetLoaded('homepage-merge-requests-loaded');
          markHomepageWidgetLoaded('homepage-activity-loaded');
          markHomepageWidgetLoaded('homepage-quick-access-loaded');
        });

        it('sets the widgets loaded mark and its measures', () => {
          expect(window.performance.mark).toHaveBeenCalledWith('homepage-widgets-loaded');
          expect(window.performance.measure).toHaveBeenCalledWith(
            'homepage-widgets',
            undefined,
            'homepage-widgets-loaded',
          );
          expect(window.performance.measure).toHaveBeenCalledWith(
            'homepage-widgets-after-mount',
            'homepage-app-mounted',
            'homepage-widgets-loaded',
          );
        });

        it('does not record the widgets loaded mark again on later loads', () => {
          markHomepageWidgetLoaded('homepage-todos-loaded');

          expect(
            window.performance.mark.mock.calls.filter(
              ([name]) => name === 'homepage-widgets-loaded',
            ),
          ).toHaveLength(1);
        });
      });
    });

    describe('when the app mount was not recorded', () => {
      it('does not set the widget mark', () => {
        markHomepageWidgetLoaded('homepage-todos-loaded');

        expect(window.performance.mark).not.toHaveBeenCalled();
        expect(window.performance.measure).not.toHaveBeenCalled();
      });
    });
  });
});
