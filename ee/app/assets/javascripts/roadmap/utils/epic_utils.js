export const addIsChildEpicTrueProperty = (obj) => ({ ...obj, isChildEpic: true });

export const generateKey = (epic) => `${epic.isChildEpic ? 'child-epic-' : 'epic-'}${epic.id}`;

// Scrolls only the roadmap shell, horizontally. `scrollIntoView` would also scroll ancestors
// and vertically, which can push the toolbar under the panel header.
export const scrollToCurrentDay = (parentEl) => {
  const todayIndicatorEl = parentEl.querySelector('.js-current-day-indicator');
  const shellEl = parentEl.closest('.js-roadmap-shell');
  if (!todayIndicatorEl || !shellEl) {
    return;
  }

  const indicatorRect = todayIndicatorEl.getBoundingClientRect();
  const shellRect = shellEl.getBoundingClientRect();
  const indicatorCenter = indicatorRect.left - shellRect.left + shellEl.scrollLeft;

  shellEl.scrollLeft = indicatorCenter + indicatorRect.width / 2 - shellEl.clientWidth / 2;
};

/**
 * Returns transformed `filterParams` by congregating all `not` params into a
 * single object like { not: { labelName: [], ... }, authorUsername: '' }
 *
 * @param {Object} filterParams
 */
export const transformFetchEpicFilterParams = (filterParams) => {
  if (!filterParams) {
    return filterParams;
  }

  const newParams = {};

  Object.keys(filterParams).forEach((param) => {
    if (param.startsWith('not')) {
      // Get the param name like `authorUsername` from `not[authorUsername]`
      const key = param.match(/not\[(.+)\]/)[1];

      if (key) {
        newParams.not = newParams.not || {};
        newParams.not[key] = filterParams[param];
      }
    } else if (param.startsWith('or')) {
      // Get the param name like `authorUsername` from `not[authorUsername]`
      const key = param.match(/or\[(.+)\]/)[1];

      if (key) {
        newParams.or = newParams.or || {};
        newParams.or[key] = filterParams[param];
      }
    } else {
      newParams[param] = filterParams[param];
    }
  });

  return newParams;
};
