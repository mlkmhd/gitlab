// An object dimension value carrying no `id` names a record that exists but cannot be told
// from another of its kind, so a row holding one never pairs. An absent value is different:
// it is the query's own NULL bucket, so it keeps an ordinary key and pairs like any other.
const UNIDENTIFIED = Symbol('unidentified');

// Identity, deliberately not the display label: two distinct records can share a label (two
// users named "Alex Smith"), and pairing on the label compares one against the other.
const identityOf = (value) => {
  if (value == null) return null;
  if (typeof value !== 'object') return String(value);

  return value.id ?? UNIDENTIFIED;
};

// Null when the row holds a value nothing can name, which has to short-circuit: JSON renders
// a symbol as null too, so an absent value would otherwise key alike. It keeps an absent
// value apart from any string that reads like one.
export const rowKeyOf = (node, dimensions) => {
  const identities = dimensions.map((dimension) => identityOf(node[dimension.key]));
  if (identities.includes(UNIDENTIFIED)) return null;

  return JSON.stringify(identities);
};
