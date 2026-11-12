import MockAdapter from 'axios-mock-adapter';
import { marked } from 'marked';
import { EDITOR_READY_EVENT } from '~/editor/constants';
import { CiSchemaExtension } from '~/editor/extensions/source_editor_ci_schema_ext';
import { EditorMarkdownExtension } from '~/editor/extensions/source_editor_markdown_ext';
import { EditorMarkdownPreviewExtension } from '~/editor/extensions/source_editor_markdown_livepreview_ext';
import { ToolbarExtension } from '~/editor/extensions/source_editor_toolbar_ext';
import { themes } from '~/ide/lib/themes';
import { sanitize } from '~/lib/dompurify';
import axios from '~/lib/utils/axios_utils';
import SourceEditor from '~/vue_shared/components/source_editor.vue';

const PREVIEW_MARKDOWN_PATH = '/preview_markdown';

export default {
  component: SourceEditor,
  title: 'editor/source_editor',
};

const Template = (args, { argTypes }) => ({
  components: { SourceEditor },
  props: Object.keys(argTypes),
  template: '<div class="gl-h-48"><source-editor v-bind="$props" /></div>',
});

export const Default = Template.bind({});
Default.args = {
  fileName: 'greeting.js',
  value: `export const greet = (name) => \`Hello, \${name}!\`;

export default greet;
`,
};

export const ReadOnly = Template.bind({});
ReadOnly.args = {
  ...Default.args,
  editorOptions: { readOnly: true },
};

export const DarkTheme = (args, { argTypes }) => ({
  components: { SourceEditor },
  props: Object.keys(argTypes),
  data() {
    return { editorKey: 0 };
  },
  computed: {
    editorProps() {
      const { colorScheme, ...editorProps } = this.$props;
      return editorProps;
    },
  },
  watch: {
    // Monaco reads the scheme when the editor is created, so a new scheme needs a new editor.
    colorScheme: {
      immediate: true,
      handler(scheme) {
        window.gon.user_color_scheme = scheme;
        this.editorKey += 1;
      },
    },
  },
  beforeCreate() {
    this.originalScheme = window.gon.user_color_scheme;
  },
  beforeDestroy() {
    window.gon.user_color_scheme = this.originalScheme;
  },
  template: '<div class="gl-h-48"><source-editor :key="editorKey" v-bind="editorProps" /></div>',
});
DarkTheme.args = {
  ...Default.args,
  colorScheme: 'dark',
};
DarkTheme.argTypes = {
  colorScheme: {
    control: 'select',
    options: themes.map(({ name }) => name),
  },
};
DarkTheme.parameters = {
  docs: {
    // Monaco themes apply to every editor on the page, so the docs page renders this story in its own iframe.
    story: { inline: false, iframeHeight: 240 },
  },
};

export const CiYamlWithSchema = (args, { argTypes }) => ({
  components: { SourceEditor },
  props: Object.keys(argTypes),
  methods: {
    registerCiSchema({ detail: { instance } }) {
      instance.use({ definition: CiSchemaExtension });
      instance.registerCiSchema();
    },
  },
  readyEvent: EDITOR_READY_EVENT,
  template: `<div class="gl-h-48">
    <source-editor v-bind="$props" @[$options.readyEvent]="registerCiSchema" />
  </div>`,
});
CiYamlWithSchema.args = {
  fileName: '.gitlab-ci.yml',
  value: `build:
  stage: build
  script: make
  when: sometimes
`,
};

export const MarkdownWithToolbar = (args, { argTypes }) => ({
  components: { SourceEditor },
  props: Object.keys(argTypes),
  // The toolbar extension mounts into #editor-toolbar, as on the blob edit page.
  template: `<div class="gl-h-48">
    <div id="editor-toolbar"></div>
    <source-editor v-bind="$props" />
  </div>`,
});
MarkdownWithToolbar.args = {
  fileName: 'README.md',
  value: `# Getting started

Some **bold** text and a [link](https://docs.gitlab.com).
`,
  extensions: [{ definition: ToolbarExtension }, { definition: EditorMarkdownExtension }],
};
MarkdownWithToolbar.parameters = {
  docs: {
    description: {
      story:
        'Loads `ToolbarExtension`, which mounts a toolbar into `#editor-toolbar`, and `EditorMarkdownExtension`, which adds the Markdown formatting buttons to it.',
    },
  },
};

export const MarkdownLivePreview = (args, { argTypes }) => ({
  components: { SourceEditor },
  props: Object.keys(argTypes),
  // Storybook has no backend, so the preview request renders the editor's Markdown in the browser.
  created() {
    this.mock = new MockAdapter(axios, { onNoMatch: 'passthrough' });
    this.mock
      .onPost(PREVIEW_MARKDOWN_PATH)
      .reply(({ data }) => [200, { body: sanitize(marked.parse(JSON.parse(data).text)) }]);
  },
  beforeDestroy() {
    this.mock.restore();
  },
  methods: {
    // Opens the preview on load. Cmd/Ctrl+Shift+P toggles it.
    showPreview({ detail: { instance } }) {
      instance.use({
        definition: EditorMarkdownPreviewExtension,
        setupOptions: { previewMarkdownPath: PREVIEW_MARKDOWN_PATH },
      });
      instance.togglePreview();
    },
  },
  readyEvent: EDITOR_READY_EVENT,
  template: `<div class="gl-h-48">
    <source-editor v-bind="$props" @[$options.readyEvent]="showPreview" />
  </div>`,
});
MarkdownLivePreview.args = {
  fileName: 'README.md',
  value: `# Getting started

Some **bold** text.
`,
};
