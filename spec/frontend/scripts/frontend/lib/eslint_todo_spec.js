/* eslint-disable import-x/extensions -- Jest does not resolve `.mjs` without it */
import {
  addIndexExport,
  getEnabledRules,
  getListedFiles,
  groupOffendingFiles,
  keepUnparsedEntries,
  removeIndexExport,
  todoFileName,
} from '../../../../../scripts/frontend/lib/eslint_todo.mjs';

const ROOT = '/repo';

describe('eslint_todo', () => {
  describe('todoFileName', () => {
    it.each`
      rule                                     | fileName
      ${'tailwindcss/no-arbitrary-value'}      | ${'tailwindcss-no-arbitrary-value.mjs'}
      ${'@gitlab/no-hardcoded-urls'}           | ${'gitlab-no-hardcoded-urls.mjs'}
      ${'@graphql-eslint/selection-set-depth'} | ${'graphql-eslint-selection-set-depth.mjs'}
    `('returns $fileName for $rule', ({ rule, fileName }) => {
      expect(todoFileName(rule)).toBe(fileName);
    });
  });

  describe('getEnabledRules', () => {
    it('returns rules that are enabled in at least one config', () => {
      const config = [
        { rules: { 'rule-a': 'error', 'rule-b': 'off' } },
        { files: ['spec/**'], rules: { 'rule-a': 'off', 'rule-c': ['warn', {}] } },
        { rules: { 'rule-d': 0, 'rule-e': ['off'], 'rule-f': 2 } },
        { ignores: ['tmp/**'] },
      ];

      expect([...getEnabledRules(config)].sort()).toEqual(['rule-a', 'rule-c', 'rule-f']);
    });
  });

  describe('getListedFiles', () => {
    it('returns the files each todo list exempts, by rule', () => {
      const todoLists = {
        ruleA: { files: ['a.js'], rules: { 'rule-a': 'off' } },
        ruleB: { files: ['b.js'], rules: { 'rule-b': 'off' } },
      };

      expect(getListedFiles(todoLists)).toEqual(
        new Map([
          ['rule-a', ['a.js']],
          ['rule-b', ['b.js']],
        ]),
      );
    });
  });

  describe('groupOffendingFiles', () => {
    const result = (file, messages) => ({ filePath: `${ROOT}/${file}`, messages });

    it('groups files by rule, sorted and without duplicates', () => {
      const results = [
        result('b.js', [{ ruleId: 'rule-a' }, { ruleId: 'rule-a' }]),
        result('a.js', [{ ruleId: 'rule-a' }, { ruleId: 'rule-b' }]),
        result('c.js', []),
      ];

      const { offendingFiles, fatalErrors } = groupOffendingFiles(
        results,
        ['rule-a', 'rule-b'],
        ROOT,
      );

      expect(offendingFiles.get('rule-a')).toEqual(['a.js', 'b.js']);
      expect(offendingFiles.get('rule-b')).toEqual(['a.js']);
      expect(fatalErrors).toEqual([]);
    });

    it('returns an empty list for rules without offenses', () => {
      const { offendingFiles } = groupOffendingFiles([], ['rule-a'], ROOT);

      expect(offendingFiles.get('rule-a')).toEqual([]);
    });

    it('ignores messages from other rules and directives', () => {
      const results = [result('a.js', [{ ruleId: 'vue/comment-directive' }, { ruleId: null }])];

      const { offendingFiles } = groupOffendingFiles(results, ['rule-a'], ROOT);

      expect(offendingFiles.get('rule-a')).toEqual([]);
    });

    it('collects fatal errors separately', () => {
      const results = [
        result('a.graphql', [{ fatal: true, ruleId: null, message: 'Parse error' }]),
      ];

      const { fatalErrors } = groupOffendingFiles(results, ['rule-a'], ROOT);

      expect(fatalErrors).toEqual([{ file: 'a.graphql', message: 'Parse error' }]);
    });
  });

  describe('keepUnparsedEntries', () => {
    it('keeps listed files that could not be parsed', () => {
      const offending = ['b.js'];
      const listed = ['a.graphql', 'c.js'];
      const unparsed = new Set(['a.graphql', 'd.graphql']);

      expect(keepUnparsedEntries(offending, listed, unparsed)).toEqual(['a.graphql', 'b.js']);
    });
  });

  // Built at runtime: Jest's dependency extractor would treat a literal export statement in this
  // file as an import of `./rule-a.mjs` and fail to resolve it.
  const exportLine = (name, file) => `export { default as ${name} } from ${`'./${file}'`};`;
  const ruleA = exportLine('ruleA', 'rule-a.mjs');
  const ruleAb = exportLine('ruleAb', 'rule-ab.mjs');

  describe('addIndexExport', () => {
    const index = `${ruleA}\n`;

    it('appends the export for a new rule', () => {
      expect(addIndexExport(index, 'rule-ab')).toBe(`${index}\n${ruleAb}`);
    });

    it('leaves the index unchanged when the export exists', () => {
      expect(addIndexExport(index, 'rule-a')).toBe(index);
    });
  });

  describe('removeIndexExport', () => {
    it('removes only the export for the given rule', () => {
      const index = [ruleA, '', ruleAb, ''].join('\n');

      expect(removeIndexExport(index, 'rule-a')).toBe(`\n${ruleAb}\n`);
    });
  });
});
