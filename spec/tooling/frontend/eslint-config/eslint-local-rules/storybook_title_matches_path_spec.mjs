import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { RuleTester } from 'eslint';
import { describe, expect, it } from 'vitest';
import {
  expectedStoryTitle,
  storybookTitleMatchesPath,
} from '../../../../../tooling/eslint-config/eslint-local-rules/storybook_title_matches_path';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../../..');
const inRoot = (file) => path.join(ROOT, file);

const FOSS_STORY = inRoot('app/assets/javascripts/vue_shared/components/source_editor.stories.js');
const EE_STORY = inRoot('ee/app/assets/javascripts/insights/components/insights_page.stories.js');
const OUTSIDE_ROOT_STORY = path.join(
  path.dirname(ROOT),
  'ee/app/assets/javascripts/foo.stories.js',
);

describe('expectedStoryTitle', () => {
  it.each`
    filename                                                                     | title
    ${FOSS_STORY}                                                                | ${'vue_shared/components/source_editor'}
    ${EE_STORY}                                                                  | ${'ee/insights/components/insights_page'}
    ${inRoot('jh/app/assets/javascripts/foo/bar.stories.js')}                    | ${'jh/foo/bar'}
    ${inRoot('app/assets/javascripts/explore/data_table/data_table.stories.js')} | ${'explore/data_table/data_table'}
    ${inRoot('app/assets/javascripts/foo/bar.js')}                               | ${null}
    ${inRoot('storybook/stories/foo.stories.js')}                                | ${null}
    ${OUTSIDE_ROOT_STORY}                                                        | ${null}
  `('returns $title for $filename', ({ filename, title }) => {
    expect(expectedStoryTitle(filename)).toBe(title);
  });
});

const ruleTester = new RuleTester({
  languageOptions: {
    ecmaVersion: 2022,
    sourceType: 'module',
  },
});

ruleTester.run('storybook-title-matches-path', storybookTitleMatchesPath, {
  valid: [
    {
      filename: FOSS_STORY,
      code: `export default { component: {}, title: 'vue_shared/components/source_editor' };`,
    },
    {
      filename: FOSS_STORY,
      code: 'export default { title: `vue_shared/components/source_editor` };',
    },
    {
      filename: EE_STORY,
      code: `
const meta = { title: 'ee/insights/components/insights_page' };
export default meta;
      `,
    },
    {
      // Files outside the stories globs aren't Storybook stories.
      filename: inRoot('spec/frontend/foo.stories.js'),
      code: `export default { title: 'anything' };`,
    },
    {
      // A default export that isn't an object literal can't be checked statically.
      filename: FOSS_STORY,
      code: `export default buildMeta();`,
    },
  ],
  invalid: [
    {
      filename: FOSS_STORY,
      code: `export default { title: 'vue_shared/source_editor' };`,
      output: `export default { title: 'vue_shared/components/source_editor' };`,
      errors: [
        { messageId: 'mismatch', data: { expected: 'vue_shared/components/source_editor' } },
      ],
    },
    {
      filename: EE_STORY,
      code: `
const meta = { title: 'insights/components/insights_page' };
export default meta;
      `,
      output: `
const meta = { title: 'ee/insights/components/insights_page' };
export default meta;
      `,
      errors: [{ messageId: 'mismatch' }],
    },
    {
      filename: EE_STORY,
      code: `
export const meta = { title: 'insights/components/insights_page' };
export default meta;
      `,
      output: `
export const meta = { title: 'ee/insights/components/insights_page' };
export default meta;
      `,
      errors: [{ messageId: 'mismatch' }],
    },
    {
      filename: FOSS_STORY,
      code: `export default { 'title': 'vue_shared/source_editor' };`,
      output: `export default { 'title': 'vue_shared/components/source_editor' };`,
      errors: [{ messageId: 'mismatch' }],
    },
    {
      // A computed title is reported but not rewritten.
      filename: FOSS_STORY,
      code: `export default { title: PREFIX + '/source_editor' };`,
      output: null,
      errors: [{ messageId: 'mismatch' }],
    },
    {
      // A missing title is reported, not added.
      filename: FOSS_STORY,
      code: `export default { component: {} };`,
      output: null,
      errors: [
        { messageId: 'missingTitle', data: { expected: 'vue_shared/components/source_editor' } },
      ],
    },
  ],
});
