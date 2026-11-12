import { enclosingBlock, fieldAtPosition } from 'ee/ai/catalog/flow_editor/include_context';
import { FLOW_INCLUDE_BLOCKS } from './mock_data';

const lines = FLOW_INCLUDE_BLOCKS.split('\n');
const lineOf = (needle, nth = 0) =>
  lines.map((l, i) => (l.includes(needle) ? i : -1)).filter((i) => i >= 0)[nth];

describe('include_context', () => {
  describe('enclosingBlock', () => {
    it.each`
      needle                    | nth  | expected
      ${'item_id: "43"'}        | ${0} | ${'include'}
      ${'item_id: 47'}          | ${0} | ${'include'}
      ${'item_id: "*"'}         | ${0} | ${'include'}
      ${'item_id: "43"'}        | ${1} | ${'subagents'}
      ${'type: AgentComponent'} | ${0} | ${null}
      ${'environment:'}         | ${0} | ${null}
    `('finds $expected for "$needle" (occurrence $nth)', ({ needle, nth, expected }) => {
      expect(enclosingBlock(lines, lineOf(needle, nth))).toBe(expected);
    });

    it('finds the parent key when the sequence is flush with it', () => {
      const flush = 'include:\n- source: ai-catalog\n  item_id: "43"\n'.split('\n');

      expect(enclosingBlock(flush, 2)).toBe('include');
    });
  });

  describe('fieldAtPosition', () => {
    const at = (needle, nth, offsetInLine) =>
      fieldAtPosition(FLOW_INCLUDE_BLOCKS, {
        lineNumber: lineOf(needle, nth) + 1,
        column: offsetInLine,
      });

    it('describes a quoted value under include', () => {
      const line = lines[lineOf('item_id: "43"', 0)];
      const col = line.indexOf('"43"') + 2;

      expect(at('item_id: "43"', 0, col)).toEqual({
        valueStart: line.indexOf('"43"') + 2,
        valueEnd: line.indexOf('"43"') + 4,
        source: 'ai-catalog',
      });
    });

    it('gives the source of a non-catalog entry', () => {
      const line = lines[lineOf('item_id: "*"', 0)];

      expect(at('item_id: "*"', 0, line.indexOf('"*"') + 2)).toMatchObject({ source: 'workspace' });
    });

    it('describes an unquoted value under include', () => {
      const line = lines[lineOf('item_id: 47', 0)];
      const col = line.indexOf('47') + 1;

      expect(at('item_id: 47', 0, col)).toMatchObject({ source: 'ai-catalog' });
    });

    it('describes a value under subagents', () => {
      const line = lines[lineOf('item_id: "43"', 1)];

      expect(at('item_id: "43"', 1, line.indexOf('"43"') + 2)).toMatchObject({
        source: 'ai-catalog',
      });
    });

    it('returns null when the cursor is before the value', () => {
      expect(at('item_id: "43"', 0, 3)).toBeNull();
    });

    it('returns null on a line that is not item_id', () => {
      expect(at('item_type: agent', 0, 14)).toBeNull();
    });

    it('describes a value in a sequence flush with its parent key', () => {
      const text = 'include:\n- source: ai-catalog\n  item_id: "43"\n';

      expect(fieldAtPosition(text, { lineNumber: 3, column: 14 })).toEqual({
        valueStart: 13,
        valueEnd: 15,
        source: 'ai-catalog',
      });
    });

    it('describes an empty value the user is about to type', () => {
      const text = 'include:\n  - source: ai-catalog\n    item_id: ""\n';

      expect(fieldAtPosition(text, { lineNumber: 3, column: 15 })).toEqual({
        valueStart: 15,
        valueEnd: 15,
        source: 'ai-catalog',
      });
    });
  });
});
