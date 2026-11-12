<script>
import PipelineEditorDrawerSection from '../pipeline_editor_drawer_section.vue';

export default {
  name: 'VisualizeAndLintSection',
  components: {
    PipelineEditorDrawerSection,
  },
};
</script>
<template>
  <pipeline-editor-drawer-section
    emoji="bulb"
    :title="s__('PipelineEditorTutorial|Tip: Visualize and validate your pipeline')"
  >
    <p class="gl-mb-0">
      {{
        s__(
          'PipelineEditorTutorial|Use the Visualize and Lint tabs in the pipeline editor to visualize your pipeline and check for any errors or warnings before committing your changes.',
        )
      }}
    </p>
  </pipeline-editor-drawer-section>
</template>
