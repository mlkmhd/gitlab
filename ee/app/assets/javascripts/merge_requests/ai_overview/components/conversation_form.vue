<script>
import { GlButton } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import { projectPreviewMarkdownPath } from '~/lib/utils/path_helpers/project';
import { MERGE_REQUEST_NOTEABLE_TYPE } from '~/notes/constants';
import MarkdownEditor from '~/vue_shared/components/markdown/markdown_editor.vue';

export default {
  name: 'ConversationForm',
  components: {
    GlButton,
    MarkdownEditor,
  },
  inject: ['projectPath', 'iid'],
  props: {
    placeholder: {
      type: String,
      required: true,
    },
    submitText: {
      type: String,
      required: true,
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
    autofocus: {
      type: Boolean,
      required: false,
      default: true,
    },
    cancelable: {
      type: Boolean,
      required: false,
      default: true,
    },
  },
  emits: ['submit', 'cancel'],
  data() {
    return {
      body: '',
    };
  },
  computed: {
    markdownPreviewPath() {
      return projectPreviewMarkdownPath(this.projectPath, {
        target_type: MERGE_REQUEST_NOTEABLE_TYPE,
        target_id: this.iid,
      });
    },
    formFieldProps() {
      return {
        placeholder: this.placeholder,
        'aria-label': this.placeholder,
        class: 'note-textarea js-gfm-input markdown-area',
        'data-testid': 'conversation-form-input',
      };
    },
  },
  methods: {
    submit() {
      if (this.body && !this.loading) this.$emit('submit', this.body);
    },
  },
  markdownDocsPath: helpPagePath('user/markdown'),
  MERGE_REQUEST_NOTEABLE_TYPE,
};
</script>

<template>
  <form class="gl-flex gl-flex-col gl-gap-2" @submit.prevent="submit">
    <markdown-editor
      v-model="body"
      :render-markdown-path="markdownPreviewPath"
      :markdown-docs-path="$options.markdownDocsPath"
      :form-field-props="formFieldProps"
      :autofocus="autofocus"
      :disabled="loading"
      :noteable-type="$options.MERGE_REQUEST_NOTEABLE_TYPE"
      supports-quick-actions
      @keydown.meta.enter="submit"
      @keydown.ctrl.enter="submit"
    />
    <div class="gl-flex gl-gap-2">
      <gl-button
        type="submit"
        variant="confirm"
        size="small"
        :disabled="!body"
        :loading="loading"
        data-testid="conversation-form-submit"
      >
        {{ submitText }}
      </gl-button>
      <gl-button v-if="cancelable" size="small" category="tertiary" @click="$emit('cancel')">
        {{ __('Cancel') }}
      </gl-button>
    </div>
  </form>
</template>
