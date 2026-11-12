<script>
import { GlLink, GlSprintf } from '@gitlab/ui';
import { s__ } from '~/locale';
import Tracking from '~/tracking';
import { DOCS_URL } from '~/constants';
import { pipelineEditorTrackingOptions } from '../../../constants';
import PipelineEditorDrawerSection from '../pipeline_editor_drawer_section.vue';

export default {
  name: 'FirstPipelineSection',
  i18n: {
    listItems: [
      s__(
        'PipelineEditorTutorial|Commit the file to your repository. The pipeline then runs automatically.',
      ),
      s__('PipelineEditorTutorial|The pipeline status is at the top of the page.'),
      s__(
        'PipelineEditorTutorial|Select the pipeline ID to view the full details about your first pipeline run.',
      ),
    ],
  },
  components: {
    GlLink,
    GlSprintf,
    PipelineEditorDrawerSection,
  },
  mixins: [Tracking.mixin()],
  methods: {
    trackHelpPageClick() {
      const { label, actions } = pipelineEditorTrackingOptions;
      this.track(actions.helpDrawerLinks.runners, { label });
    },
  },
  RUNNER_HELP_URL: `${DOCS_URL}/runner/register/index.html`,
};
</script>
<template>
  <pipeline-editor-drawer-section
    emoji="rocket"
    :title="s__('PipelineEditorTutorial|Run your first pipeline')"
  >
    <p class="gl-mb-3">
      {{ s__('PipelineEditorTutorial|This template creates a simple test pipeline. To use it:') }}
    </p>
    <ol class="gl-mb-3">
      <li v-for="(item, i) in $options.i18n.listItems" :key="`li-${i}`">{{ item }}</li>
    </ol>
    <p class="gl-mb-0">
      <gl-sprintf
        :message="
          s__(
            'PipelineEditorTutorial|If you’re using a self-managed GitLab instance, %{linkStart}make sure your instance has runners available.%{linkEnd}',
          )
        "
      >
        <template #link="{ content }">
          <gl-link :href="$options.RUNNER_HELP_URL" target="_blank" @click="trackHelpPageClick()">
            {{ content }}
          </gl-link>
        </template>
      </gl-sprintf>
    </p>
  </pipeline-editor-drawer-section>
</template>
