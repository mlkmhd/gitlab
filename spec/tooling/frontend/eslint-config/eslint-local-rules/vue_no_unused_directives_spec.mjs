import { RuleTester } from 'eslint';
import vueEslintParser from 'vue-eslint-parser';
import {
  vueNoUnusedDirectives,
  MESSAGE_IDS,
} from '../../../../../tooling/eslint-config/eslint-local-rules/vue_no_unused_directives';

const ruleTester = new RuleTester({
  languageOptions: {
    parser: vueEslintParser,
    ecmaVersion: 2022,
    sourceType: 'module',
  },
});

const sfc = (template, directives) => `
<script>
import { GlTooltipDirective } from '@gitlab/ui';
import SafeHtml from '~/vue_shared/directives/safe_html';

export default {
  directives: ${directives},
};
</script>
<template>${template}</template>
`;

const unused = (key, templateName) => ({
  messageId: MESSAGE_IDS.unused,
  data: { key, templateName },
});

ruleTester.run('vue-no-unused-directives', vueNoUnusedDirectives, {
  valid: [
    sfc('<div v-gl-tooltip title="a"></div>', '{ GlTooltip: GlTooltipDirective }'),
    sfc('<div v-gl-tooltip.bottom="a"></div>', '{ GlTooltip: GlTooltipDirective }'),
    sfc('<div v-safe-html="a"></div>', '{ SafeHtml }'),
    sfc('<div v-safe-html:[config]="a"></div>', '{ SafeHtml }'),
    sfc('<div v-safe-html="a"></div>', "{ 'safe-html': SafeHtml }"),
    sfc('<div v-safe-html="a"></div>', '{ safeHtml: SafeHtml }'),
    sfc('<template #default><span v-safe-html="a"></span></template>', '{ SafeHtml }'),
    // Multiple roots: a directive used only in a later root still counts.
    sfc('<div v-if="a"></div><div v-else v-gl-tooltip></div>', '{ GlTooltip: GlTooltipDirective }'),
    // Not statically readable.
    sfc('<div></div>', 'getDirectives()'),
    sfc('<div></div>', '{ [name]: SafeHtml }'),
    `
      <script>
      import SafeHtml from '~/vue_shared/directives/safe_html';
      export default {
        directives: { SafeHtml },
        render(h) { return h('div'); },
      };
      </script>
    `,
  ],
  invalid: [
    {
      code: sfc('<div></div>', '{ GlTooltip: GlTooltipDirective }'),
      errors: [unused('GlTooltip', 'gl-tooltip')],
    },
    {
      code: sfc('<div v-safe-html="a"></div>', '{ GlTooltip: GlTooltipDirective, SafeHtml }'),
      errors: [unused('GlTooltip', 'gl-tooltip')],
    },
    {
      code: sfc('<div v-gl-tooltip-directive></div>', '{ GlTooltip: GlTooltipDirective }'),
      errors: [unused('GlTooltip', 'gl-tooltip')],
    },
    {
      code: sfc('<div :title="a"></div>', '{ GlTooltip: GlTooltipDirective, SafeHtml }'),
      errors: [unused('GlTooltip', 'gl-tooltip'), unused('SafeHtml', 'safe-html')],
    },
    {
      code: sfc(
        '<div v-if="a"></div><div v-else v-safe-html="b"></div>',
        '{ GlTooltip: GlTooltipDirective, SafeHtml }',
      ),
      errors: [unused('GlTooltip', 'gl-tooltip')],
    },
  ],
});
