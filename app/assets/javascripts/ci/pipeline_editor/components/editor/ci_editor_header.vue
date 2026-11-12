<script>
import { GlButton, GlLink } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import { exploreCatalogIndexPath } from '~/lib/utils/path_helpers/explore';
import Tracking from '~/tracking';
import glFeatureFlagMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import {
  EDITOR_APP_DRAWER_HELP,
  EDITOR_APP_DRAWER_JOB_ASSISTANT,
  EDITOR_APP_DRAWER_NONE,
  pipelineEditorTrackingOptions,
} from '../../constants';

export default {
  name: 'CiEditorHeader',
  components: {
    GlButton,
    GlLink,
  },
  mixins: [glFeatureFlagMixin(), Tracking.mixin()],
  props: {
    showHelpDrawer: {
      type: Boolean,
      required: true,
    },
    showJobAssistantDrawer: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['switch-drawer'],
  computed: {
    exploreCatalogIndexPath() {
      return exploreCatalogIndexPath();
    },
    editorA11yHelpPagePath() {
      return helpPagePath('ci/pipeline_editor/_index.md', {
        anchor: 'editor-accessibility-options',
      });
    },
  },
  methods: {
    toggleHelpDrawer() {
      if (this.showHelpDrawer) {
        this.$emit('switch-drawer', EDITOR_APP_DRAWER_NONE);
      } else {
        this.$emit('switch-drawer', EDITOR_APP_DRAWER_HELP);
        this.trackHelpDrawerClick();
      }
    },
    toggleJobAssistantDrawer() {
      this.$emit(
        'switch-drawer',
        this.showJobAssistantDrawer ? EDITOR_APP_DRAWER_NONE : EDITOR_APP_DRAWER_JOB_ASSISTANT,
      );
    },
    trackCatalogBrowsing() {
      const { label, actions } = pipelineEditorTrackingOptions;

      this.track(actions.browseCatalog, { label });
    },
    trackHelpDrawerClick() {
      const { label, actions } = pipelineEditorTrackingOptions;
      this.track(actions.openHelpDrawer, { label });
    },
  },
};
</script>

<template>
  <div
    class="gl-flex gl-flex-col gl-gap-3 gl-rounded-t-lg gl-border-1 gl-border-solid gl-border-default gl-p-3 @md/panel:gl-flex-row @md/panel:gl-items-center"
  >
    <slot></slot>
    <gl-button
      :href="exploreCatalogIndexPath"
      size="small"
      icon="catalog-checkmark"
      target="_blank"
      data-testid="catalog-repo-link"
      @click="trackCatalogBrowsing"
    >
      {{ __('CI/CD Catalog') }}
    </gl-button>
    <gl-button
      icon="information-o"
      size="small"
      data-testid="drawer-toggle"
      @click="toggleHelpDrawer"
    >
      {{ __('Help') }}
    </gl-button>
    <gl-button
      v-if="glFeatures.ciJobAssistantDrawer"
      icon="bulb"
      size="small"
      @click="toggleJobAssistantDrawer"
    >
      {{ s__('JobAssistant|Job assistant') }}
    </gl-button>
    <gl-link
      class="gl-p-2 gl-text-center"
      :href="editorA11yHelpPagePath"
      data-testid="editor-accessibility-link"
    >
      {{ s__('PipelineEditor|Editor accessibility guide') }}
    </gl-link>
  </div>
</template>
