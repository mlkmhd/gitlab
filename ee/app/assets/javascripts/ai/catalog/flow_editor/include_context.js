export const BLOCK_INCLUDE = 'include';
export const BLOCK_SUBAGENTS = 'subagents';
export const FIELD_ITEM_ID = 'item_id';
export const FIELD_SOURCE = 'source';
export const SOURCE_AI_CATALOG = 'ai-catalog';

const KEY_LINE = /^(\s*)(-\s+)?(?<key>[A-Za-z_][\w-]*):/;
const valueLine = (key) =>
  new RegExp(
    `^(\\s*)(-\\s+)?${key}:\\s*(?<openQuote>["']?)(?<value>[^"'\\s#]*)(?<closeQuote>["']?)\\s*$`,
  );

// A dash list marker is "- ", so the field under it starts two columns after the dash.
const DASH_MARKER_WIDTH = 2;

const indentOf = (line) => line.match(/^\s*/)[0].length;
const isBlank = (line) => {
  const trimmed = line.trim();
  return !trimmed || trimmed.startsWith('#');
};
const isListItem = (line) => line.trim().startsWith('-');

function entryDashIndex(lines, lineIndex) {
  const keyIndent = indentOf(lines[lineIndex]);
  for (let i = lineIndex; i >= 0; i -= 1) {
    if (isBlank(lines[i])) continue;
    const indent = indentOf(lines[i]);
    if (indent > keyIndent) continue;
    if (isListItem(lines[i])) return i;
    if (indent < keyIndent) return null;
  }
  return null;
}

function entryField(lines, lineIndex, key) {
  const dashIndex = entryDashIndex(lines, lineIndex);
  if (dashIndex === null) return null;

  const fieldIndent = lines[dashIndex].indexOf('-') + DASH_MARKER_WIDTH;
  const pattern = valueLine(key);

  for (let i = dashIndex; i < lines.length; i += 1) {
    const line = lines[i];
    if (isBlank(line)) continue;
    if (i > dashIndex && (indentOf(line) < fieldIndent || isListItem(line))) break;
    const match = line.match(pattern);
    if (match) return match.groups.value;
  }
  return null;
}

export function enclosingBlock(lines, lineIndex) {
  const dashIndex = entryDashIndex(lines, lineIndex);
  if (dashIndex === null) return null;

  const dashIndent = indentOf(lines[dashIndex]);
  for (let i = dashIndex - 1; i >= 0; i -= 1) {
    if (isBlank(lines[i])) continue;
    const indent = indentOf(lines[i]);
    // Deeper lines belong to a sibling entry; same-indent dashes are sibling entries.
    // A flush sequence puts the parent key at the dash indent, so it is the first
    // non-list line at that indent or less.
    if (indent > dashIndent || isListItem(lines[i])) continue;
    const key = lines[i].match(KEY_LINE)?.groups.key;
    return key === BLOCK_INCLUDE || key === BLOCK_SUBAGENTS ? key : null;
  }
  return null;
}

export function fieldAtPosition(text, position) {
  const lines = text.split('\n');
  const lineIndex = position.lineNumber - 1;
  const line = lines[lineIndex];
  if (line === undefined) return null;

  const match = line.match(valueLine(FIELD_ITEM_ID));
  if (!match) return null;

  const block = enclosingBlock(lines, lineIndex);
  if (!block) return null;

  const { openQuote, value, closeQuote } = match.groups;
  const prefixLength = line.indexOf(`${FIELD_ITEM_ID}:`) + FIELD_ITEM_ID.length + 1;
  const leading = line.slice(prefixLength).match(/^\s*/)[0].length;
  // Columns are 1-based, so the first value character sits one past the prefix and quote.
  const valueStart = prefixLength + leading + openQuote.length + 1;
  const valueEnd = valueStart + value.length;

  if (position.column < valueStart || position.column > valueEnd + closeQuote.length) return null;

  return {
    valueStart,
    valueEnd,
    source: entryField(lines, lineIndex, FIELD_SOURCE),
  };
}
