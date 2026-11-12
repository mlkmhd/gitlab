<script>
import { GlAlert, GlButton, GlForm, GlIcon } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { TYPENAME_VULNERABILITY } from '~/graphql_shared/constants';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { s__ } from '~/locale';
import securityAiFlowFeedbackCreateMutation from './graphql/security_ai_flow_feedback_create.mutation.graphql';
import { SENTIMENT } from './constants';

export default {
  name: 'SecurityAiFlowFeedback',
  components: {
    GlAlert,
    GlButton,
    GlForm,
    GlIcon,
  },
  props: {
    /**
     * ID of the vulnerability. The feedback is about its latest AI assessment.
     * State is not reset when this changes, so key the component by this ID.
     */
    vulnerabilityId: {
      type: Number,
      required: true,
    },
    /**
     * Reasons a user can pick when they disagree, as `{ value, text }` objects.
     * `value` must be a value of the `SecurityAiFlowFeedbackReason` GraphQL enum.
     */
    reasons: {
      type: Array,
      required: false,
      default: () => [],
      validator: (reasons) =>
        reasons.every(
          (reason) => typeof reason?.value === 'string' && typeof reason?.text === 'string',
        ),
    },
    /**
     * Question shown above the Yes and No buttons.
     */
    question: {
      type: String,
      required: false,
      default: s__('SecurityAiFlowFeedback|Is this assessment correct?'),
    },
  },
  emits: ['submitted'],
  data() {
    return {
      isSubmitted: false,
      isSaving: false,
      errorMessage: null,
      selectedSentiment: null,
      selectedReasons: [],
      disagreeSectionId: uniqueId('security-ai-flow-feedback-disagree-'),
    };
  },
  computed: {
    isFormOpen() {
      return this.isDisagreeSelected;
    },
    isAgreeSelected() {
      return this.selectedSentiment === SENTIMENT.AGREE;
    },
    isDisagreeSelected() {
      return this.selectedSentiment === SENTIMENT.DISAGREE;
    },
  },
  methods: {
    isReasonSelected(value) {
      return this.selectedReasons.includes(value);
    },
    toggleReason(value) {
      this.selectedReasons = this.isReasonSelected(value)
        ? this.selectedReasons.filter((reason) => reason !== value)
        : [...this.selectedReasons, value];
    },
    resetSelection() {
      this.errorMessage = null;
      this.selectedSentiment = null;
      this.selectedReasons = [];
    },
    agree() {
      this.resetSelection();
      this.selectedSentiment = SENTIMENT.AGREE;
      this.submit();
    },
    toggleDisagree() {
      if (this.isFormOpen) {
        this.cancel();
        return;
      }

      this.selectedSentiment = SENTIMENT.DISAGREE;
      this.errorMessage = null;
      this.focusRef(this.reasons.length ? 'reasonButtons' : 'submitButton');
    },
    cancel() {
      this.resetSelection();
      this.focusRef('disagreeButton');
    },
    async submit() {
      // Sent in display order, so the same reasons always produce the same event value.
      const reasons = this.reasons
        .filter(({ value }) => this.isReasonSelected(value))
        .map(({ value }) => value);
      const feedback = { sentiment: this.selectedSentiment, reasons };

      this.isSaving = true;
      this.errorMessage = null;

      let errors;
      try {
        const { data } = await this.$apollo.mutate({
          mutation: securityAiFlowFeedbackCreateMutation,
          variables: {
            input: {
              vulnerabilityId: convertToGraphQLId(TYPENAME_VULNERABILITY, this.vulnerabilityId),
              ...feedback,
            },
          },
        });

        errors = data.securityAiFlowFeedbackCreate.errors;
      } catch (error) {
        Sentry.captureException(error);
        this.showError(s__("SecurityAiFlowFeedback|Feedback couldn't be saved. Try again."));
        return;
      }

      if (errors.length) {
        this.showError(errors[0]);
        return;
      }

      this.isSaving = false;
      this.isSubmitted = true;
      this.focusRef('submittedMessage');
      this.$emit('submitted', feedback);
    },
    showError(message) {
      this.isSaving = false;
      this.errorMessage = message;
      this.focusRef(this.isFormOpen ? 'submitButton' : 'agreeButton');
    },
    async focusRef(ref) {
      await this.$nextTick();
      const [target] = [this.$refs[ref]].flat();
      (target?.$el ?? target)?.focus();
    },
  },
};
</script>

<template>
  <div>
    <div v-if="isSubmitted" class="gl-flex gl-flex-wrap gl-items-center gl-gap-3">
      <gl-icon name="check-circle" variant="success" />
      <!-- tabindex="-1" lets focus move here once the form it replaces is removed. -->
      <span
        ref="submittedMessage"
        tabindex="-1"
        class="gl-text-subtle"
        data-testid="security-ai-flow-feedback-submitted-message"
      >
        {{ s__('SecurityAiFlowFeedback|Thanks for your feedback.') }}
      </span>
    </div>

    <gl-form v-else data-testid="security-ai-flow-feedback-form" @submit.prevent="submit">
      <fieldset class="gl-flex gl-flex-col gl-gap-4">
        <legend class="gl-mb-3 gl-border-0 gl-text-base gl-font-bold">{{ question }}</legend>

        <div class="gl-flex gl-flex-wrap gl-gap-3">
          <gl-button
            ref="agreeButton"
            icon="thumb-up"
            :disabled="isSaving"
            :selected="isAgreeSelected"
            :loading="isSaving && isAgreeSelected"
            data-testid="security-ai-flow-feedback-agree-button"
            @click="agree"
          >
            {{ __('Yes') }}
          </gl-button>
          <gl-button
            ref="disagreeButton"
            icon="thumb-down"
            :disabled="isSaving"
            :selected="isDisagreeSelected"
            :aria-expanded="String(isFormOpen)"
            :aria-controls="disagreeSectionId"
            data-testid="security-ai-flow-feedback-disagree-button"
            @click="toggleDisagree"
          >
            {{ __('No') }}
          </gl-button>
        </div>

        <div
          v-if="isFormOpen"
          :id="disagreeSectionId"
          class="gl-flex gl-flex-col gl-gap-4"
          data-testid="security-ai-flow-feedback-disagree-section"
        >
          <fieldset v-if="reasons.length" data-testid="security-ai-flow-feedback-reasons">
            <legend class="gl-mb-2 gl-border-0 gl-text-base">
              {{ s__("SecurityAiFlowFeedback|What's wrong? (optional)") }}
            </legend>
            <div class="gl-flex gl-flex-wrap gl-gap-2">
              <gl-button
                v-for="reason in reasons"
                ref="reasonButtons"
                :key="reason.value"
                size="small"
                class="!gl-rounded-full"
                :disabled="isSaving"
                :icon="isReasonSelected(reason.value) ? 'check' : ''"
                :selected="isReasonSelected(reason.value)"
                :aria-pressed="String(isReasonSelected(reason.value))"
                :data-testid="`security-ai-flow-feedback-reason-${reason.value}`"
                @click="toggleReason(reason.value)"
              >
                {{ reason.text }}
              </gl-button>
            </div>
          </fieldset>

          <!-- @slot Extra controls for the disagree form, for example a follow-up action.
               Disable them while the `disabled` slot prop is true. -->
          <slot name="disagree-extra" :disabled="isSaving" />
        </div>

        <gl-alert v-if="errorMessage" variant="danger" :dismissible="false">
          {{ errorMessage }}
        </gl-alert>

        <div v-if="isFormOpen" class="gl-flex gl-flex-wrap gl-gap-3">
          <gl-button
            ref="submitButton"
            type="submit"
            variant="confirm"
            :loading="isSaving"
            data-testid="security-ai-flow-feedback-submit-button"
          >
            {{ s__('SecurityAiFlowFeedback|Submit feedback') }}
          </gl-button>
          <gl-button
            :disabled="isSaving"
            data-testid="security-ai-flow-feedback-cancel-button"
            @click="cancel"
          >
            {{ __('Cancel') }}
          </gl-button>
        </div>
      </fieldset>
    </gl-form>
  </div>
</template>
