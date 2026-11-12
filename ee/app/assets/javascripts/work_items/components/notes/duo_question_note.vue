<script>
import { GlButton, GlCollapse, GlIcon } from '@gitlab/ui';
import { xor } from 'lodash-es';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { clearDraft } from '~/lib/utils/autosave';
import { getCurrentUser } from '~/lib/utils/common_utils';
import { s__ } from '~/locale';
import createNoteMutation from '~/work_items/graphql/notes/create_work_item_note.mutation.graphql';
import toggleResolveDiscussionMutation from '~/work_items/graphql/notes/toggle_work_item_note_resolve_discussion.mutation.graphql';
import { ANSWER_ID_CUSTOM, PARSE_STATUS_OK, QUESTION_TYPE_CLOSED } from '../../constants';
import {
  buildDuoAnswer,
  buildDuoAnswers,
  parseDuoAnswer,
  parseDuoAnswerLabels,
  parseDuoQuestion,
  stripDuoAnswerMarker,
} from '../../utils/duo_question';
import {
  resolveDuoQuestionDecision,
  updateDuoQuestionDecision,
} from '../../utils/duo_question_decision';
import DuoCustomAnswerInput from './duo_custom_answer_input.vue';
import DuoMultiSelectOptions from './duo_multi_select_options.vue';
import DuoSingleSelectOptions from './duo_single_select_options.vue';

/**
 * Renders the clarifying question a workplan flow attached to its comment, so a
 * choice can be made in the discussion instead of by typing prose back at the agent.
 *
 * Answering posts the choice as a reply and resolves the thread, which marks the
 * question as answered. The paused workflow resumes with the replies once someone
 * continues it from the Workplan widget.
 *
 * Not gated by the `workplan` flag: only that flow posts this payload, and its
 * questions stay answerable if the flag is turned off after they were asked.
 *
 * An answer can also be written out when no option fits. That reply carries
 * `ANSWER_ID_CUSTOM`, so a decision log can tell a typed answer from a picked one.
 *
 * A resolved answer can be changed to another offered option. That posts a new reply,
 * which the card reads as the latest answer, and updates the resolved decision to match.
 */
export default {
  name: 'DuoQuestionNote',
  components: {
    GlButton,
    GlCollapse,
    GlIcon,
    DuoCustomAnswerInput,
    DuoMultiSelectOptions,
    DuoSingleSelectOptions,
  },
  props: {
    note: {
      type: Object,
      required: true,
    },
    workItemId: {
      type: String,
      required: true,
    },
    fullPath: {
      type: String,
      required: true,
    },
    workItemIid: {
      type: String,
      required: true,
    },
    discussionId: {
      type: String,
      required: true,
    },
    replies: {
      type: Array,
      required: true,
    },
    isDiscussionResolved: {
      type: Boolean,
      required: true,
    },
    isDiscussionResolvable: {
      type: Boolean,
      required: true,
    },
    canReply: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['duo-question-answered', 'error'],
  data() {
    return {
      submittingId: null,
      answeredId: null,
      submittedCustomAnswer: '',
      selectedIds: [],
      customAnswer: '',
      submittedLabels: [],
      customAnswerResets: 0,
      showOptions: false,
      isChangingAnswer: false,
    };
  },
  computed: {
    question() {
      const result = parseDuoQuestion(this.note.body);
      if (result.status !== PARSE_STATUS_OK) return null;

      // An open question has nothing to pick from, so the prose above is already the
      // whole interaction.
      const { question } = result;

      return question.type === QUESTION_TYPE_CLOSED ? question : null;
    },
    options() {
      return this.question?.options ?? [];
    },
    // Read back so the answer survives page reloads.
    // Once the thread is resolved, the latest marker wins
    // since anyone can reply but only some can resolve the
    // thread and mark answer as accepted.
    answerReply() {
      if (!this.isDiscussionResolved) return undefined;

      return this.replies.findLast((reply) => parseDuoAnswer(reply.body));
    },
    // Falls back to this session's answer, before the reply reaches the Apollo cache.
    answerId() {
      return this.answeredId ?? parseDuoAnswer(this.answerReply?.body);
    },
    chosenOption() {
      return this.options.find((option) => option.id === this.answerId) ?? null;
    },
    customAnswerText() {
      if (this.answerId !== ANSWER_ID_CUSTOM) return '';

      return this.submittedCustomAnswer || stripDuoAnswerMarker(this.answerReply?.body);
    },
    isMultiple() {
      return Boolean(this.question?.multiple);
    },
    answeredLabels() {
      if (this.isMultiple) {
        if (this.submittedLabels.length) return this.submittedLabels;

        return this.answerReply ? parseDuoAnswerLabels(this.answerReply.body) : [];
      }

      if (this.chosenOption) return [this.chosenOption.label];

      return this.customAnswerText ? [this.customAnswerText] : [];
    },
    isAnswered() {
      return this.answeredLabels.length > 0;
    },
    isResolvedWithoutAnswer() {
      return this.isDiscussionResolved && !this.isAnswered;
    },
    isResolvedWithAnswer() {
      return this.isDiscussionResolved && this.isAnswered;
    },
    chosenIds() {
      return this.answerId?.split(',') ?? [];
    },
    unchosenOptions() {
      return this.options.filter((option) => !this.chosenIds.includes(option.id));
    },
    displayedOptions() {
      return this.isAnswered && !this.isChangingAnswer ? this.unchosenOptions : this.options;
    },
    areOptionsCollapsible() {
      if (this.isChangingAnswer) return false;

      return (
        this.isResolvedWithoutAnswer ||
        (this.isResolvedWithAnswer && this.unchosenOptions.length > 0)
      );
    },
    // Changing an answer settles the question again, so it takes the same rights as answering it.
    canChangeAnswer() {
      return (
        this.isResolvedWithAnswer &&
        this.canReply &&
        this.isDiscussionResolvable &&
        !this.isChangingAnswer
      );
    },
    areOptionsVisible() {
      return !this.areOptionsCollapsible || this.showOptions;
    },
    optionsToggleLabel() {
      if (this.isAnswered) {
        return this.showOptions
          ? s__('WorkItemDuoQuestion|Hide other suggested answers')
          : s__('WorkItemDuoQuestion|Show other suggested answers');
      }

      return this.showOptions
        ? s__('WorkItemDuoQuestion|Hide suggested answers')
        : s__('WorkItemDuoQuestion|Show suggested answers');
    },
    selectedOptions() {
      const picked = this.options.filter((option) => this.selectedIds.includes(option.id));

      return this.customAnswer
        ? [...picked, { id: ANSWER_ID_CUSTOM, label: this.customAnswer }]
        : picked;
    },
    hasSelectionChanged() {
      return xor(this.selectedIds, this.chosenIds).length > 0;
    },
    canSubmitSelection() {
      return (
        this.selectedOptions.length > 0 &&
        !this.isSubmitting &&
        (!this.isChangingAnswer || this.hasSelectionChanged)
      );
    },
    isSubmitting() {
      return Boolean(this.submittingId);
    },
    // Answering posts a note, so a user who cannot comment is offered nothing to
    // click: the options stay visible, since they record what the agent weighed.
    isDisabled() {
      return this.isSubmitting || !this.canReply || this.areOptionsCollapsible;
    },
    isSubmittingCustomAnswer() {
      return this.submittingId === ANSWER_ID_CUSTOM;
    },
    customResponseDraftKey() {
      return `${this.discussionId}-duo-answer`;
    },
    // Unique per card, since a work item can show several question threads at once.
    customAnswerInputId() {
      return `duo-custom-answer-${this.note.id}`;
    },
    customAnswerInputKey() {
      return `${this.customAnswerInputId}-${this.customAnswerResets}`;
    },
    optionsId() {
      return `duo-question-options-${this.note.id}`;
    },
  },
  methods: {
    answer(option) {
      if (this.isChangingAnswer && option.id === this.answerId) {
        this.stopChangingAnswer();
        return undefined;
      }

      return this.postAnswer({ id: option.id, body: buildDuoAnswer(option) });
    },
    async startChangingAnswer() {
      // A typed answer cannot be changed here, so only offered picks carry over.
      this.selectedIds = this.options
        .filter((option) => this.chosenIds.includes(option.id))
        .map(({ id }) => id);
      this.customAnswer = '';
      this.isChangingAnswer = true;

      // The clicked control unmounts, so focus would otherwise fall back to the page body.
      await this.$nextTick();
      this.$refs.optionList?.focus();
    },
    async stopChangingAnswer() {
      this.selectedIds = [];
      this.isChangingAnswer = false;

      await this.$nextTick();
      this.$refs.changeAnswer?.$el.focus();
    },
    submitSelection() {
      const { selectedOptions } = this;

      return this.postAnswer({
        id: selectedOptions.map(({ id }) => id).join(','),
        body: buildDuoAnswers(selectedOptions),
        onAnswered: () => {
          this.submittedLabels = selectedOptions.map(({ label }) => label);
          clearDraft(this.customResponseDraftKey);
        },
      });
    },
    submitCustomAnswer(label) {
      return this.postAnswer({
        id: ANSWER_ID_CUSTOM,
        body: buildDuoAnswer({ id: ANSWER_ID_CUSTOM, label }),
        onAnswered: () => {
          this.submittedCustomAnswer = label;
          clearDraft(this.customResponseDraftKey);
        },
      });
    },
    async postAnswer({ id, body, onAnswered }) {
      this.submittingId = id;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: createNoteMutation,
          variables: {
            input: {
              noteableId: this.workItemId,
              discussionId: this.discussionId,
              body,
              internal: this.note.internal,
            },
          },
        });

        if (data?.createNote?.errors?.length) {
          throw new Error(data.createNote.errors.join(', '));
        }

        // Answering and resolving happen together, so a user who cannot resolve only
        // gets the reply posted. Nothing is settled, and the options remain clickable.
        if (!this.isDiscussionResolvable) {
          this.clearSelection();
          return;
        }

        this.answeredId = id;
        onAnswered?.();
        if (this.isChangingAnswer) {
          this.stopChangingAnswer();
          updateDuoQuestionDecision({
            apolloClient: this.$apollo.getClient(),
            fullPath: this.fullPath,
            workItemIid: this.workItemIid,
            discussionId: this.discussionId,
            questionNote: this.note,
            answerNote: { id: data.createNote.note.id, body },
            currentUserId: getCurrentUser({ useGlobalId: true })?.id,
          });
        } else if (await this.resolveThread()) {
          resolveDuoQuestionDecision({
            apolloClient: this.$apollo.getClient(),
            fullPath: this.fullPath,
            workItemIid: this.workItemIid,
            discussionId: this.discussionId,
            questionNote: this.note,
            answerNote: { id: data.createNote.note.id, body },
          });
        }
        this.$emit('duo-question-answered');
      } catch (error) {
        this.$emit(
          'error',
          s__(
            'WorkItemDuoQuestion|Something went wrong while sending your answer. Please try again.',
          ),
        );
        Sentry.captureException(error);
      } finally {
        this.submittingId = null;
      }
    },
    clearSelection() {
      this.selectedIds = [];
      clearDraft(this.customResponseDraftKey);
      this.customAnswerResets += 1;
    },
    // A failure here must not read as the answer failing, since the reply is already
    // posted. It does need saying, though: resolving is what signals the question is
    // settled, so an unresolved thread leaves the run waiting.
    async resolveThread() {
      if (this.isDiscussionResolved) return false;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: toggleResolveDiscussionMutation,
          variables: { id: this.discussionId, resolve: true },
        });

        const errors = data?.discussionToggleResolve?.errors;
        if (errors?.length) throw new Error(errors.join(', '));

        return true;
      } catch (error) {
        this.$emit(
          'error',
          s__(
            'WorkItemDuoQuestion|Your answer was posted, but the thread could not be resolved. Resolve it manually so GitLab Duo can continue.',
          ),
        );
        Sentry.captureException(error);
        return false;
      }
    },
  },
};
</script>

<template>
  <div v-if="question" class="gl-mt-3 gl-flex gl-flex-col gl-gap-3" data-testid="duo-question-note">
    <ul
      v-if="isAnswered && !isChangingAnswer"
      class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-3 gl-p-0"
    >
      <li
        v-for="(label, index) in answeredLabels"
        :key="index"
        class="gl-flex gl-min-h-8 gl-items-start gl-gap-3 gl-rounded-lg gl-border-1 gl-border-solid gl-border-default gl-bg-subtle gl-px-4 gl-py-3"
        data-testid="duo-answer"
      >
        <gl-icon name="check" variant="success" class="gl-mt-1 gl-shrink-0" />
        <span>{{ label }}</span>
      </li>
    </ul>

    <div v-if="areOptionsCollapsible || canChangeAnswer" class="gl-flex gl-flex-wrap gl-gap-x-5">
      <gl-button
        v-if="areOptionsCollapsible"
        :aria-controls="optionsId"
        :aria-expanded="String(showOptions)"
        variant="link"
        class="!gl-text-sm"
        data-testid="duo-question-options-toggle"
        @click="showOptions = !showOptions"
        >{{ optionsToggleLabel }}</gl-button
      >
      <gl-button
        v-if="canChangeAnswer"
        ref="changeAnswer"
        variant="link"
        class="!gl-text-sm"
        data-testid="duo-question-change-answer"
        @click="startChangingAnswer"
        >{{ s__('WorkItemDuoQuestion|Change answer') }}</gl-button
      >
    </div>

    <gl-collapse
      v-if="!isAnswered || areOptionsCollapsible || isChangingAnswer"
      :id="optionsId"
      :visible="areOptionsVisible"
    >
      <div class="gl-flex gl-flex-col gl-gap-3">
        <duo-multi-select-options
          v-if="isMultiple && !areOptionsCollapsible"
          ref="optionList"
          :options="displayedOptions"
          :checked-ids="selectedIds"
          :disabled="isDisabled"
          @input="selectedIds = $event"
        />
        <duo-single-select-options
          v-else
          ref="optionList"
          :options="displayedOptions"
          :disabled="isDisabled"
          :submitting-id="submittingId"
          :unchosen="areOptionsCollapsible"
          @select="answer"
        />

        <template v-if="canReply && !areOptionsCollapsible">
          <duo-custom-answer-input
            v-if="!isChangingAnswer"
            :key="customAnswerInputKey"
            :draft-key="customResponseDraftKey"
            :input-id="customAnswerInputId"
            :disabled="isDisabled"
            :submitting="isSubmittingCustomAnswer"
            :multiple="isMultiple"
            @submit="submitCustomAnswer"
            @change="customAnswer = $event"
          />

          <div v-if="isMultiple || isChangingAnswer" class="gl-flex gl-gap-3">
            <gl-button
              v-if="isMultiple"
              :disabled="!canSubmitSelection"
              :loading="isSubmitting"
              variant="confirm"
              data-testid="duo-question-submit"
              @click="submitSelection"
              >{{ s__('WorkItemDuoQuestion|Submit') }}</gl-button
            >
            <gl-button
              v-if="isChangingAnswer"
              :disabled="isSubmitting"
              data-testid="duo-question-cancel-change"
              @click="stopChangingAnswer"
              >{{ __('Cancel') }}</gl-button
            >
          </div>
        </template>
      </div>
    </gl-collapse>
  </div>
</template>
