import { s__ } from '~/locale';
import { dimensionsOf } from '../../../utils/chart_data';
import { rowKeyOf } from './row_key';

// Reserved keys the table adds to each row. A compiled GLQL field key comes from query text,
// which cannot produce these, so they can never collide with a real field.
export const CHILD_ROWS_KEY = '__children';
export const ROW_KEY = '__rowKey';

/**
 * The dimension the breakdown adds to the table's, or null unless it adds exactly one: none
 * means it repeats a dimension the table already has, and several mean it adds a list.
 */
export const childDimensionOf = (parentFields, childFields) => {
  const parentKeys = dimensionsOf(parentFields).map(({ key }) => key);
  const added = dimensionsOf(childFields).filter(({ key }) => !parentKeys.includes(key));

  return added.length === 1 ? added[0] : null;
};

// Returns a node's row key, or null when another node shares it: several rows a `group`
// dimension cannot resolve all key alike, and nothing can tell them apart.
const uniqueRowKeyOf = (nodes, dimensions) => {
  const counts = new Map();
  nodes.forEach((node) => {
    const key = rowKeyOf(node, dimensions);
    if (key !== null) counts.set(key, (counts.get(key) ?? 0) + 1);
  });

  return (node) => {
    const key = rowKeyOf(node, dimensions);

    return counts.get(key) === 1 ? key : null;
  };
};

/**
 * Nests each child row under the parent row with the same parent dimensions. The breakdown
 * is the table's query with one more dimension, so a child carries its parent's dimension
 * values. A NULL bucket pairs like any other row, so a top-level group's own projects nest
 * under its "Not in a subgroup" row. Children whose parent is not loaded yet are left out, and
 * so are those of a parent whose key is not its own.
 */
export const withChildRows = (parents, children, { parentDimensions, childDimensions }) => {
  const parentKeyOf = uniqueRowKeyOf(parents, parentDimensions);
  const childKeyOf = uniqueRowKeyOf(children, childDimensions);

  const childrenByParentKey = new Map();
  children.forEach((child) => {
    const parentKey = rowKeyOf(child, parentDimensions);
    if (parentKey === null) return;

    const siblings = childrenByParentKey.get(parentKey) ?? [];
    siblings.push({ ...child, [ROW_KEY]: childKeyOf(child) });
    childrenByParentKey.set(parentKey, siblings);
  });

  return parents.map((parent) => {
    const key = parentKeyOf(parent);

    return {
      ...parent,
      [ROW_KEY]: key,
      [CHILD_ROWS_KEY]: (key !== null && childrenByParentKey.get(key)) || [],
    };
  });
};

/**
 * Joins a breakdown into a table's input, so each row carries the rows nested under it.
 * `dimension` is the one the breakdown adds, null until it lands, and `error` is set unless
 * it adds exactly one. Until then, each row gets its key and no children, so it can expand.
 * `truncatedCount` is how many breakdown rows loaded when it stopped short of its total, or
 * null when it is complete.
 */
export const withBreakdown = ({ fields, data, breakdownData }) => {
  const dimension = breakdownData ? childDimensionOf(fields, breakdownData.fields) : null;
  const nodes = withChildRows(data.nodes, dimension ? breakdownData.nodes : [], {
    parentDimensions: dimensionsOf(fields),
    childDimensions: dimension ? dimensionsOf(breakdownData.fields) : [],
  });

  return {
    data: { ...data, nodes },
    dimension,
    truncatedCount:
      dimension && breakdownData.count > breakdownData.nodes.length
        ? breakdownData.nodes.length
        : null,
    error:
      breakdownData && !dimension
        ? s__('Glql|`expandRowsBy` must name one dimension the query does not already use.')
        : null,
  };
};
