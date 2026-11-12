<script>
import { GlLink, GlIcon } from '@gitlab/ui';
import { __, s__ } from '~/locale';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import VulnerabilityContextFlowLastRun from 'ee/vulnerabilities/components/vulnerability_context_flow_last_run.vue';
import PipelineStatusBadge from './pipeline_status_badge.vue';

export default {
  name: 'ProjectPipelineStatus',
  components: {
    GlLink,
    GlIcon,
    TimeAgoTooltip,
    PipelineStatusBadge,
    VulnerabilityContextFlowLastRun,
  },
  props: {
    pipeline: { type: Object, required: true },
    sbomPipeline: { type: Object, required: false, default: null },
  },
  computed: {
    parsingStatusMessage() {
      return this.parseStatusMessage(this.pipeline);
    },
    sbomParsingStatusMessage() {
      return this.parseStatusMessage(this.sbomPipeline);
    },
    showSbomPipelineStatus() {
      return Boolean(this.sbomPipeline?.id);
    },
  },
  methods: {
    parseStatusMessage(pipeline) {
      const { hasParsingErrors, hasParsingWarnings } = pipeline;

      if (hasParsingErrors && hasParsingWarnings) {
        return this.$options.i18n.hasParsingErrorsAndWarnings;
      }
      if (hasParsingErrors) {
        return this.$options.i18n.hasParsingErrors;
      }
      if (hasParsingWarnings) {
        return this.$options.i18n.hasParsingWarnings;
      }

      return '';
    },
  },
  i18n: {
    lastUpdated: __('Security reports last updated'),
    hasParsingErrorsAndWarnings: s__('SecurityReports|Parsing errors and warnings in pipeline'),
    hasParsingErrors: s__('SecurityReports|Parsing errors in pipeline'),
    hasParsingWarnings: s__('SecurityReports|Parsing warnings in pipeline'),
    sbomLastUpdated: __('SBOMs last updated'),
  },
};
</script>

<template>
  <div class="gl-border-b gl-flex-wrap gl-gap-x-6 gl-gap-y-4 gl-bg-subtle gl-p-5 @lg/panel:gl-flex">
    <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-y-2" data-testid="pipeline">
      <span class="gl-mr-3 gl-inline-flex gl-shrink-0 gl-items-center gl-font-bold">
        <gl-icon name="pipeline" class="gl-mr-2" />{{ $options.i18n.lastUpdated }}
      </span>
      <span class="gl-flex gl-items-center gl-whitespace-nowrap">
        <time-ago-tooltip class="gl-pr-3" :time="pipeline.createdAt" /><gl-link
          :href="pipeline.path"
          >#{{ pipeline.id }}</gl-link
        >
        <pipeline-status-badge :pipeline="pipeline" class="gl-ml-3" />
      </span>
      <div
        v-if="parsingStatusMessage"
        class="gl-ml-3 gl-font-bold gl-text-warning"
        data-testid="parsing-status-notice"
      >
        <gl-icon name="warning" class="gl-mr-3" />{{ parsingStatusMessage }}
      </div>
    </div>

    <div
      v-if="showSbomPipelineStatus"
      class="gl-mt-5 gl-items-center @md/panel:gl-flex @lg/panel:gl-mt-0"
      data-testid="sbom-pipeline"
    >
      <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-y-2">
        <span class="gl-mr-3 gl-inline-flex gl-shrink-0 gl-items-center gl-font-bold">
          <gl-icon name="package" class="gl-mr-2" />{{ $options.i18n.sbomLastUpdated }}
        </span>
        <span class="gl-flex gl-items-center gl-whitespace-nowrap">
          <time-ago-tooltip class="gl-pr-3" :time="sbomPipeline.createdAt" /><gl-link
            :href="sbomPipeline.path"
            >#{{ sbomPipeline.id }}</gl-link
          >
          <pipeline-status-badge :pipeline="sbomPipeline" class="gl-ml-3" />
        </span>
      </div>
      <div
        v-if="sbomParsingStatusMessage"
        class="gl-ml-2 gl-mt-5 gl-font-bold gl-text-warning @md/panel:gl-mt-0"
        data-testid="parsing-status-notice"
      >
        <gl-icon name="warning" class="gl-mr-3" />{{ sbomParsingStatusMessage }}
      </div>
    </div>

    <vulnerability-context-flow-last-run bold-label class="gl-mt-5 @lg/panel:gl-mt-0" />
  </div>
</template>
