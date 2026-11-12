import { RuleTester } from 'eslint';
import vueEslintParser from 'vue-eslint-parser';
import { vueNoSingleUseI18nKeys } from '../../../../../tooling/eslint-config/eslint-local-rules/vue_no_single_use_i18n_keys';

const ruleTester = new RuleTester({
  languageOptions: {
    parser: vueEslintParser,
    ecmaVersion: 2022,
    sourceType: 'module',
  },
});

const sfc = (script, template = '<div />') =>
  `<script>\n${script}\n</script>\n<template>${template}</template>`;

const usedOnce = (key) => ({ messageId: 'usedOnce', data: { key } });
const unused = (key) => ({ messageId: 'unused', data: { key } });

ruleTester.run('vue-no-single-use-i18n-keys', vueNoSingleUseI18nKeys, {
  valid: [
    {
      // Inline translations.
      filename: 'test.vue',
      code: `<template><span>{{ s__('Foo|Bar') }}</span></template>`,
    },
    {
      // A key read twice may stay.
      filename: 'test.vue',
      code: sfc(
        `export default { i18n: { title: s__('Foo|Bar') } };`,
        `<div><h1>{{ $options.i18n.title }}</h1><p>{{ $options.i18n.title }}</p></div>`,
      ),
    },
    {
      // Read in the template and in the script.
      filename: 'test.vue',
      code: sfc(
        `export default {
  i18n: { saveError: s__('Foo|Bar') },
  methods: { onError() { createAlert({ message: this.$options.i18n.saveError }); } },
};`,
        `<p>{{ $options.i18n.saveError }}</p>`,
      ),
    },
    {
      // Dynamic reads cannot be counted.
      filename: 'test.vue',
      code: sfc(`export default { i18n: { a: __('A') } };`, `<p>{{ $options.i18n[key] }}</p>`),
    },
    {
      // Destructuring cannot be counted.
      filename: 'test.vue',
      code: sfc(
        `export default { i18n: { a: __('A') }, methods: { f() { const { a } = this.$options.i18n; return a; } } };`,
      ),
    },
    {
      // Passed whole.
      filename: 'test.vue',
      code: sfc(`export default { i18n: { a: __('A') } };`, `<child :i18n="$options.i18n" />`),
    },
    {
      // Not an object literal.
      filename: 'test.vue',
      code: sfc(`export default { i18n: I18N };`, `<p>{{ $options.i18n.title }}</p>`),
    },
    {
      // Lookup maps are indexed at runtime, so they cannot be inlined.
      filename: 'test.vue',
      code: sfc(
        `export default { i18n: { statusLabels: { success: __('Passed'), failed: __('Failed') } } };`,
        `<p>{{ $options.i18n.statusLabels[status] }}</p>`,
      ),
    },
    {
      // Plural functions are called with a count.
      filename: 'test.vue',
      code: sfc(
        `export default { i18n: { count: (n) => n__('%d item', '%d items', n) } };`,
        `<p>{{ $options.i18n.count(n) }}</p>`,
      ),
    },
    {
      // A read split across lines is still a read.
      filename: 'test.vue',
      code: sfc(
        `export default {
  i18n: { a: __('A') },
  methods: { f() { return [this.$options.i18n
    .a, this.$options.i18n.a]; } },
};`,
      ),
    },
    {
      // Destructuring `$options` cannot be counted.
      filename: 'test.vue',
      code: sfc(
        `export default { i18n: { a: __('A') }, methods: { f() { const { i18n } = this.$options; return i18n.a; } } };`,
      ),
    },
    {
      // Processed strings and arrays read once cannot be inlined as a translation call.
      filename: 'test.vue',
      code: sfc(
        `export default { i18n: { safe: sanitize(s__('Foo|Bar')), items: [__('A'), __('B')] } };`,
        `<div><p v-safe-html="$options.i18n.safe" /><li v-for="i in $options.i18n.items">{{ i }}</li></div>`,
      ),
    },
  ],
  invalid: [
    {
      filename: 'test.vue',
      code: sfc(
        `export default { i18n: { title: s__('Foo|Bar'), body: __('Baz') } };`,
        `<div><h1>{{ $options.i18n.title }}</h1><p>{{ $options.i18n.title }}</p><p>{{ $options.i18n.body }}</p></div>`,
      ),
      output: sfc(
        `export default { i18n: { title: s__('Foo|Bar') } };`,
        `<div><h1>{{ $options.i18n.title }}</h1><p>{{ $options.i18n.title }}</p><p>{{ __('Baz') }}</p></div>`,
      ),
      errors: [usedOnce('body')],
    },
    {
      // Read in the script. The only key goes, so the whole option goes.
      filename: 'test.vue',
      code: sfc(
        `export default { i18n: { title: s__('Foo|Bar') }, methods: { f() { return this.$options.i18n.title; } } };`,
      ),
      output: sfc(`export default { methods: { f() { return s__('Foo|Bar'); } } };`),
      errors: [usedOnce('title')],
    },
    {
      // Multi-line object keeps its trailing comma.
      filename: 'test.vue',
      code: sfc(
        `export default {
  i18n: {
    a: __('A'),
    b: __('B'),
  },
};`,
        `<p :title="$options.i18n.a">{{ $options.i18n.a }}{{ $options.i18n.b }}</p>`,
      ),
      output: sfc(
        `export default {
  i18n: {
    a: __('A'),
  },
};`,
        `<p :title="$options.i18n.a">{{ $options.i18n.a }}{{ __('B') }}</p>`,
      ),
      errors: [usedOnce('b')],
    },
    {
      // Read in an attribute.
      filename: 'test.vue',
      code: sfc(
        `export default { i18n: { a: __('A'), b: __('B') } };`,
        `<p :title="$options.i18n.a">{{ $options.i18n.b }}{{ $options.i18n.b }}</p>`,
      ),
      output: sfc(
        `export default { i18n: { b: __('B') } };`,
        `<p :title="__('A')">{{ $options.i18n.b }}{{ $options.i18n.b }}</p>`,
      ),
      errors: [usedOnce('a')],
    },
    {
      // Not fixed: the value's quotes clash with the attribute's.
      filename: 'test.vue',
      code: sfc(`export default { i18n: { a: __("A") } };`, `<p :title="$options.i18n.a" />`),
      output: null,
      errors: [usedOnce('a')],
    },
    {
      // `n__` with literal arguments is fixed; `sprintf` is not, its arguments reference script scope.
      filename: 'test.vue',
      code: sfc(
        `export default { i18n: { a: sprintf(__('%{n} A'), { n }), b: n__('B', 'Bs', 2) } };`,
        `<p>{{ $options.i18n.a }}{{ $options.i18n.b }}</p>`,
      ),
      output: sfc(
        `export default { i18n: { a: sprintf(__('%{n} A'), { n }) } };`,
        `<p>{{ $options.i18n.a }}{{ n__('B', 'Bs', 2) }}</p>`,
      ),
      errors: [usedOnce('a'), usedOnce('b')],
    },
    {
      // Not fixed: an argument is not a literal.
      filename: 'test.vue',
      code: sfc(
        `export default { i18n: { a: n__('A', 'As', count) } };`,
        `<p>{{ $options.i18n.a }}</p>`,
      ),
      output: null,
      errors: [usedOnce('a')],
    },
    {
      // Unread keys get a suggestion, not a fix: another module may read them.
      filename: 'test.vue',
      code: sfc(`export default { i18n: { orphan: __('Gone') } };`),
      output: null,
      errors: [
        {
          ...unused('orphan'),
          suggestions: [{ messageId: 'removeKey', output: sfc(`export default {};`) }],
        },
      ],
    },
    {
      // An unread key is reported whatever its value.
      filename: 'test.vue',
      code: sfc(`export default { i18n: { safe: sanitize(__('A')), items: [__('B')] } };`),
      output: null,
      errors: [
        {
          ...unused('safe'),
          suggestions: [
            {
              messageId: 'removeKey',
              output: sfc(`export default { i18n: { items: [__('B')] } };`),
            },
          ],
        },
        {
          ...unused('items'),
          suggestions: [
            {
              messageId: 'removeKey',
              output: sfc(`export default { i18n: { safe: sanitize(__('A')) } };`),
            },
          ],
        },
      ],
    },
    {
      // A key that prefixes another is counted on its own.
      filename: 'test.vue',
      code: sfc(
        `export default { i18n: { title: __('A'), titleLong: __('B') } };`,
        `<div>{{ $options.i18n.titleLong }}{{ $options.i18n.titleLong }}{{ $options.i18n.title }}</div>`,
      ),
      output: sfc(
        `export default { i18n: { titleLong: __('B') } };`,
        `<div>{{ $options.i18n.titleLong }}{{ $options.i18n.titleLong }}{{ __('A') }}</div>`,
      ),
      errors: [usedOnce('title')],
    },
    {
      filename: 'test.vue',
      code: sfc(
        `export default normalizeRender({ i18n: { a: __('A') } });`,
        `<p>{{ $options.i18n.a }}</p>`,
      ),
      output: sfc(`export default normalizeRender({});`, `<p>{{ __('A') }}</p>`),
      errors: [usedOnce('a')],
    },
    {
      // A comment mentioning `$options.i18n` is not a read and does not skip the file.
      filename: 'test.vue',
      code: sfc(
        `// see $options.i18n for strings, like $options.i18n.title
export default { i18n: { title: __('A') } };`,
        `<p>{{ $options.i18n.title }}</p>`,
      ),
      output: sfc(
        `// see $options.i18n for strings, like $options.i18n.title
export default {};`,
        `<p>{{ __('A') }}</p>`,
      ),
      errors: [usedOnce('title')],
    },
    {
      filename: 'test.vue',
      code: sfc(`export default { i18n: { title: __('A') } };`, `<p>{{ $options.i18n?.title }}</p>`),
      output: sfc(`export default {};`, `<p>{{ __('A') }}</p>`),
      errors: [usedOnce('title')],
    },
    {
      // No template.
      filename: 'test.vue',
      code: `<script>\nexport default { i18n: { a: __('A') }, render() { return this.$options.i18n.a; } };\n</script>`,
      output: `<script>\nexport default { render() { return __('A'); } };\n</script>`,
      errors: [usedOnce('a')],
    },
  ],
});
