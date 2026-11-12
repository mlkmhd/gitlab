import { performanceMarkAndMeasure } from '~/performance/utils';
import {
  HOMEPAGE_MARK_APP_MOUNTED,
  HOMEPAGE_MARK_TODOS_LOADED,
  HOMEPAGE_MARK_MERGE_REQUESTS_LOADED,
  HOMEPAGE_MARK_ACTIVITY_LOADED,
  HOMEPAGE_MARK_QUICK_ACCESS_LOADED,
  HOMEPAGE_MARK_WIDGETS_LOADED,
  HOMEPAGE_MARK_TAB_HIDDEN,
  HOMEPAGE_MEASURE_TODOS,
  HOMEPAGE_MEASURE_MERGE_REQUESTS,
  HOMEPAGE_MEASURE_ACTIVITY,
  HOMEPAGE_MEASURE_QUICK_ACCESS,
  HOMEPAGE_MEASURE_WIDGETS,
  HOMEPAGE_MEASURE_WIDGETS_AFTER_MOUNT,
} from '~/performance/constants';

const WIDGET_MEASURES = {
  [HOMEPAGE_MARK_TODOS_LOADED]: HOMEPAGE_MEASURE_TODOS,
  [HOMEPAGE_MARK_MERGE_REQUESTS_LOADED]: HOMEPAGE_MEASURE_MERGE_REQUESTS,
  [HOMEPAGE_MARK_ACTIVITY_LOADED]: HOMEPAGE_MEASURE_ACTIVITY,
  [HOMEPAGE_MARK_QUICK_ACCESS_LOADED]: HOMEPAGE_MEASURE_QUICK_ACCESS,
};

const hasMark = (name) => performance.getEntriesByName(name).length > 0;

// Hidden tabs pause requestAnimationFrame and run slower, which would inflate every
// measure, so a load is only recorded if the tab stays visible from mount onwards.
export const markHomepageAppMounted = () => {
  if (document.hidden) return;

  performanceMarkAndMeasure({ mark: HOMEPAGE_MARK_APP_MOUNTED });
  document.addEventListener(
    'visibilitychange',
    () => performanceMarkAndMeasure({ sync: true, mark: HOMEPAGE_MARK_TAB_HIDDEN }),
    { once: true },
  );
};

export const markHomepageWidgetLoaded = (mark) => {
  window.requestAnimationFrame(() => {
    // Skip refetches, since only the first load counts, and loads that weren't visible throughout.
    if (hasMark(mark) || !hasMark(HOMEPAGE_MARK_APP_MOUNTED) || hasMark(HOMEPAGE_MARK_TAB_HIDDEN)) {
      return;
    }

    performanceMarkAndMeasure({
      sync: true,
      mark,
      measures: [{ name: WIDGET_MEASURES[mark], end: mark }],
    });

    if (!Object.keys(WIDGET_MEASURES).every((widgetMark) => hasMark(widgetMark))) return;

    performanceMarkAndMeasure({
      sync: true,
      mark: HOMEPAGE_MARK_WIDGETS_LOADED,
      measures: [
        { name: HOMEPAGE_MEASURE_WIDGETS, end: HOMEPAGE_MARK_WIDGETS_LOADED },
        {
          name: HOMEPAGE_MEASURE_WIDGETS_AFTER_MOUNT,
          start: HOMEPAGE_MARK_APP_MOUNTED,
          end: HOMEPAGE_MARK_WIDGETS_LOADED,
        },
      ],
    });
  });
};
