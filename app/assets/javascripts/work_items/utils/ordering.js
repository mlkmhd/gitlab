// Ordering helpers shared by the board and table views. They work on ids, and the caller
// passes `getId` to say what an item's id is: the board uses getGroupId (a group's id depends
// on groupBy), the table uses the column's `key`.

// Values whose id is in `order` keep that relative order; anything else keeps
// its incoming order and goes to the end.
export const orderByIds = ({ order = [], values = [], getId }) => {
  if (!Array.isArray(order) || order.length === 0) {
    return values;
  }

  const rank = new Map(order.map((id, index) => [id, index]));
  const known = [];
  const unknown = [];

  values.forEach((value) => {
    (rank.has(getId(value)) ? known : unknown).push(value);
  });

  known.sort((a, b) => rank.get(getId(a)) - rank.get(getId(b)));

  return [...known, ...unknown];
};

// Works out the new order to save after reordering the visible columns. Slots the
// new order back into `currentOrder` so a hidden column keeps its stored spot — orderByIds
// drops stale ids later, so this doesn't need to tell hidden and stale apart.
export const reorderIds = ({ visibleIds, currentOrder = [] }) => {
  const visibleSet = new Set(visibleIds);

  const result = [];
  const placed = new Set();
  const push = (id) => {
    if (id !== undefined && !placed.has(id)) {
      result.push(id);
      placed.add(id);
    }
  };

  let nextVisible = 0;
  currentOrder.forEach((id) => {
    if (visibleSet.has(id)) {
      push(visibleIds[nextVisible]);
      nextVisible += 1;
    } else {
      push(id);
    }
  });

  // Visible columns that weren't in the stored order yet (newly added).
  while (nextVisible < visibleIds.length) {
    push(visibleIds[nextVisible]);
    nextVisible += 1;
  }

  return result;
};
