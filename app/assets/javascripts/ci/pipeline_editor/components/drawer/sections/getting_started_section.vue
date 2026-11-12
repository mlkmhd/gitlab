<script>
import { GlSprintf, GlLink } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import PipelineEditorDrawerSection from '../pipeline_editor_drawer_section.vue';

export default {
  name: 'GettingStartedSection',
  addJobsToPipelinesLink: helpPagePath('/ci/pipelines/merge_request_pipelines.html', {
    anchor: 'configure-merge-request-pipelines',
  }),
  components: {
    GlSprintf,
    GlLink,
    PipelineEditorDrawerSection,
  },
};
</script>
<template>
  <pipeline-editor-drawer-section
    emoji="wave"
    :title="s__('PipelineEditorTutorial|Get started with GitLab CI/CD')"
  >
    <p class="gl-mb-3">
      {{
        s__(
          'PipelineEditorTutorial|GitLab CI/CD can automatically build, test, and deploy your application.',
        )
      }}
    </p>
    <p class="gl-mb-0">
      <gl-sprintf
        :message="
          s__(
            'PipelineEditorTutorial|The pipeline stages and jobs are defined in a %{codeStart}.gitlab-ci.yml%{codeEnd} file. You can edit, visualize and validate the syntax in this file by using the pipeline editor. Use the %{codeStart}rules%{codeEnd} keyword to %{linkStart}configure jobs to run in merge requests%{linkEnd}.',
          )
        "
      >
        <template #code="{ content }">
          <code>{{ content }}</code>
        </template>
        <template #link="{ content }">
          <gl-link :href="$options.addJobsToPipelinesLink" target="_blank">{{ content }}</gl-link>
        </template>
      </gl-sprintf>
    </p>
  </pipeline-editor-drawer-section>
</template>
