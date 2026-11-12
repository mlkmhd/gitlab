<script>
import { GlAlert, GlBadge, GlButton, GlLink, GlLoadingIcon } from '@gitlab/ui';
import { formatNumber, s__, sprintf } from '~/locale';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { VULNERABILITY_STATES } from 'ee/vulnerabilities/constants';
import getSkillguardSkillQuery from 'ee/ai/governance/graphql/queries/get_skillguard_skill.query.graphql';
import {
  SKILLGUARD_ANALYZER_VERDICTS,
  SKILLGUARD_RISK_BANDS,
  SKILLGUARD_SEVERITY_VERDICTS,
} from 'ee/ai/governance/constants';
import { parseSkillguardDetails } from 'ee/ai/governance/utils';

const OWASP_IDENTIFIER_TYPE = 'owasp_agentic';

export default {
  name: 'SkillPanelView',
  components: {
    GlAlert,
    GlBadge,
    GlButton,
    GlLink,
    GlLoadingIcon,
    TimeAgoTooltip,
  },
  props: {
    vulnerabilityId: {
      type: String,
      required: true,
    },
  },
  apollo: {
    skill: {
      query: getSkillguardSkillQuery,
      variables() {
        return { id: this.vulnerabilityId };
      },
      update(data) {
        return data.vulnerability;
      },
      error() {
        this.hasError = true;
      },
    },
  },
  data() {
    return {
      skill: null,
      hasError: false,
    };
  },
  computed: {
    loading() {
      return this.$apollo.queries.skill.loading;
    },
    analysis() {
      return parseSkillguardDetails(this.skill?.details);
    },
    verdict() {
      const bySeverity = SKILLGUARD_SEVERITY_VERDICTS[this.skill?.severity?.toLowerCase()];

      return (
        SKILLGUARD_ANALYZER_VERDICTS[this.analysis.verdict] ||
        SKILLGUARD_ANALYZER_VERDICTS[bySeverity] ||
        null
      );
    },
    confidence() {
      const { confidence } = this.analysis;
      return confidence === null ? null : formatNumber(confidence, { style: 'percent' });
    },
    riskScore() {
      const { riskScore, riskBand } = this.analysis;
      if (riskScore === null) return null;

      const band = SKILLGUARD_RISK_BANDS[riskBand];
      return band
        ? sprintf(s__('AiGovernance|%{score} (%{band})'), { score: riskScore, band }, false)
        : String(riskScore);
    },
    status() {
      return VULNERABILITY_STATES[this.skill?.state?.toLowerCase()] || this.skill?.state;
    },
    categories() {
      return (this.skill?.identifiers || [])
        .filter(({ externalType }) => externalType === OWASP_IDENTIFIER_TYPE)
        .map(({ externalId, name }) => ({ id: externalId, name }));
    },
  },
};
</script>

<template>
  <div>
    <gl-loading-icon v-if="loading" size="lg" class="gl-mt-5" />

    <gl-alert v-else-if="hasError" variant="danger" :dismissible="false">
      {{ s__('AiGovernance|Failed to load this skill.') }}
    </gl-alert>

    <gl-alert v-else-if="!skill" variant="info" :dismissible="false" data-testid="skill-not-found">
      {{
        s__('AiGovernance|This skill could not be found, or you do not have permission to view it.')
      }}
    </gl-alert>

    <div v-else class="gl-flex gl-flex-col gl-gap-5" data-testid="skill-panel">
      <div class="gl-flex gl-flex-wrap gl-items-start gl-justify-between gl-gap-3">
        <gl-badge
          v-if="verdict"
          :variant="verdict.variant"
          :icon="verdict.icon"
          data-testid="skill-verdict"
          >{{ verdict.label }}</gl-badge
        >
        <gl-button
          :href="skill.vulnerabilityPath"
          icon="shield"
          class="gl-ml-auto"
          data-testid="skill-vulnerability-link"
          >{{ s__('AiGovernance|View in vulnerability report') }}</gl-button
        >
      </div>

      <p
        v-if="skill.description"
        class="gl-mb-0 gl-whitespace-pre-line"
        data-testid="skill-description"
      >
        {{ skill.description }}
      </p>

      <section class="gl-border gl-rounded-base gl-p-4">
        <h3 class="gl-heading-5 gl-mb-4">{{ s__('AiGovernance|Details') }}</h3>
        <dl class="gl-mb-0 gl-grid gl-grid-cols-1 gl-gap-x-5 gl-gap-y-4 @md/panel:gl-grid-cols-2">
          <div>
            <dt class="gl-text-subtle">{{ s__('AiGovernance|Status') }}</dt>
            <dd class="gl-mb-0" data-testid="skill-status">{{ status }}</dd>
          </div>
          <div>
            <dt class="gl-text-subtle">{{ s__('AiGovernance|Detected') }}</dt>
            <dd class="gl-mb-0" data-testid="skill-detected">
              <time-ago-tooltip :time="skill.detectedAt" />
            </dd>
          </div>
          <div v-if="confidence">
            <dt class="gl-text-subtle">{{ s__('AiGovernance|Confidence') }}</dt>
            <dd class="gl-mb-0" data-testid="skill-confidence">{{ confidence }}</dd>
          </div>
          <div v-if="riskScore">
            <dt class="gl-text-subtle">{{ s__('AiGovernance|Risk score') }}</dt>
            <dd class="gl-mb-0" data-testid="skill-risk-score">{{ riskScore }}</dd>
          </div>
          <div v-if="skill.location && skill.location.file">
            <dt class="gl-text-subtle">{{ s__('AiGovernance|File') }}</dt>
            <dd class="gl-mb-0 gl-break-all">
              <gl-link
                :href="skill.location.blobPath"
                class="gl-font-monospace gl-text-sm"
                data-testid="skill-file"
                >{{ skill.location.file }}</gl-link
              >
            </dd>
          </div>
          <div v-if="skill.project">
            <dt class="gl-text-subtle">{{ s__('AiGovernance|Detected in') }}</dt>
            <dd class="gl-mb-0">
              <gl-link :href="skill.project.webPath" data-testid="skill-project">{{
                skill.project.name
              }}</gl-link>
            </dd>
          </div>
        </dl>
      </section>

      <section v-if="analysis.findings.length" class="gl-border gl-rounded-base gl-p-4">
        <h3 class="gl-heading-5 gl-mb-3">{{ s__('AiGovernance|What SkillGuard found') }}</h3>
        <ol class="gl-mb-0 gl-pl-5" data-testid="skill-findings">
          <li v-for="(finding, index) in analysis.findings" :key="index">{{ finding }}</li>
        </ol>
      </section>

      <section v-if="analysis.riskFlags.length" class="gl-border gl-rounded-base gl-p-4">
        <h3 class="gl-heading-5 gl-mb-3">{{ s__('AiGovernance|Risk flags') }}</h3>
        <ul
          class="gl-mb-0 gl-flex gl-list-none gl-flex-wrap gl-gap-2 gl-p-0"
          data-testid="skill-risk-flags"
        >
          <li v-for="(flag, index) in analysis.riskFlags" :key="index">
            <gl-badge variant="neutral" class="gl-font-monospace">{{ flag }}</gl-badge>
          </li>
        </ul>
      </section>

      <section v-if="categories.length" class="gl-border gl-rounded-base gl-p-4">
        <h3 class="gl-heading-5 gl-mb-3">{{ s__('AiGovernance|OWASP agentic categories') }}</h3>
        <ul class="gl-mb-0 gl-pl-5" data-testid="skill-categories">
          <li v-for="category in categories" :key="category.id">{{ category.name }}</li>
        </ul>
      </section>
    </div>
  </div>
</template>
