import { orderByIds, reorderIds } from '~/work_items/utils/ordering';
import { getGroupId } from './identity';

export const GROUP_SORT = { ASC: 'asc', DESC: 'desc', MANUAL: 'manual' };

// Column order lives in its own `groupOrder` array, separate from `visibleGroups`/
// `collapsedGroups` — `visibleGroups` is null when everything is shown, so it can't
// double as a place to store order, and hiding a column shouldn't reorder it.
//
// Columns come from the namespace live (statuses today), so the stored order
// can drift out of sync with the real set over time. The functions below
// reconcile the two rather than trusting either one blindly.
//
// The id-based logic lives in ~/work_items/utils/ordering, shared with the table view. These
// wrappers turn board group values into ids with getGroupId.

export const orderGroups = ({ groupOrder = [], groupBy, values = [] }) =>
  orderByIds({ order: groupOrder, values, getId: (value) => getGroupId({ groupBy, value }) });

export const reorderGroupIds = ({ visibleValues, groupBy, currentOrder = [] }) =>
  reorderIds({
    visibleIds: visibleValues.map((value) => getGroupId({ groupBy, value })),
    currentOrder,
  });

// A saved groupOrder predates groupSort existing, so treat it as manual rather than
// silently dropping the column order a user already dragged into place.
export const effectiveGroupSort = ({ groupSort, groupOrder = [] } = {}) =>
  groupSort ?? (groupOrder.length > 0 ? GROUP_SORT.MANUAL : GROUP_SORT.ASC);

export const applyGroupSort = ({ values = [], groupSort, groupOrder, groupBy }) => {
  switch (effectiveGroupSort({ groupSort, groupOrder })) {
    case GROUP_SORT.MANUAL:
      return orderGroups({ groupOrder, groupBy, values });
    case GROUP_SORT.DESC:
      return [...values].reverse();
    default:
      return values;
  }
};
