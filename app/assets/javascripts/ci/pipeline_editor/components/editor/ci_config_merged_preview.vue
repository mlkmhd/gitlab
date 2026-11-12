<script>
import { GlIcon } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import SourceEditor from '~/vue_shared/components/source_editor.vue';
import { glListenersMixin } from '~/lib/utils/vue3compat/gl_listeners_mixin';

export default {
  name: 'CiConfigMergedPreview',
  components: {
    SourceEditor,
    GlIcon,
  },
  mixins: [glListenersMixin],
  inject: ['ciConfigPath'],
  props: {
    ciConfigData: {
      type: Object,
      required: true,
    },
  },
  computed: {
    fileGlobalId() {
      return `${this.ciConfigPath}-${uniqueId()}`;
    },
    mergedYaml() {
      return this.ciConfigData.mergedYaml;
    },
  },
};
</script>
<template>
  <div>
    <div class="gl-flex gl-items-center">
      <gl-icon class="gl-mr-3" :size="16" name="lock" variant="subtle" />
      {{ s__('Pipelines|Full configuration is view only') }}
    </div>
    <div class="gl-mt-3 gl-border-1 gl-border-solid gl-border-default">
      <source-editor
        ref="editor"
        :value="mergedYaml"
        :file-name="ciConfigPath"
        :file-global-id="fileGlobalId"
        :editor-options="/* eslint-disable @gitlab/vue-no-new-non-primitive-in-template */ {
          readOnly: true,
        } /* eslint-enable @gitlab/vue-no-new-non-primitive-in-template */"
        v-on="glListeners()"
      />
    </div>
  </div>
</template>
