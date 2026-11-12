import { truncate } from 'lodash-es';
import { createAlert } from '~/alert';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { fetchPolicies } from '~/lib/graphql';
import { s__ } from '~/locale';
import { DECISION_TEXT_LENGTH_MAX } from '../components/decision_log/constants';
import decisionLogQuery from '../components/decision_log/graphql/decision_log.query.graphql';
import resolveDecisionMutation from '../components/decision_log/graphql/resolve_decision.mutation.graphql';
import updateDecisionMutation from '../components/decision_log/graphql/update_decision.mutation.graphql';
import { PARSE_STATUS_OK } from '../constants';
import {
  parseDuoAnswer,
  parseDuoAnswerLabels,
  parseDuoQuestion,
  stripDuoAnswerMarker,
} from './duo_question';

/**
 * The reply that answered a question, read the same way the question card reads it: the latest
 * reply carrying an answer marker. Without one, the reply posted while resolving answers it, or
 * else the thread's latest reply, since a thread can be resolved apart from replying to it.
 * Replies from GitLab Duo itself, the question's author, never answer it.
 *
 * @param {Object} params
 * @param {Object} params.questionNote The thread's first note, which carries the question.
 * @param {Array<Object>} [params.replies] The thread's replies, oldest first.
 * @param {Object} [params.postedReply] The reply posted while resolving the thread.
 * @returns {Object|undefined} The answering reply.
 */
export const findDuoAnswerNote = ({ questionNote, replies = [], postedReply }) => {
  const candidates = (postedReply ? [...replies, postedReply] : replies).filter(
    ({ author }) => !author || author.id !== questionNote?.author?.id,
  );

  return (
    candidates.findLast(({ body }) => parseDuoAnswer(body)) ?? postedReply ?? candidates.at(-1)
  );
};

// Mirrors Ruby's `squish`, which the backend applies to option labels before storing them.
const squish = (text) => text.replace(/\s+/g, ' ').trim();

/**
 * The `workItemDecisionResolve` input for a question's decision.
 *
 * Picked labels are matched to the decision's options by content. A decision holds at most 5
 * options, so a pick beyond those is dropped until
 * https://gitlab.com/gitlab-org/gitlab/-/work_items/631184 caps options at 5. An answer written
 * in the reader's own words becomes the decision itself. When it rides along with picks, all of
 * them are written in as one comma-separated decision, since the API takes either picked options
 * or a written-in one.
 *
 * @param {Object} params
 * @param {Object} params.decision The open decision from the decision log query.
 * @param {Object} params.question The parsed Duo question the decision holds.
 * @param {Object} [params.answerNote] The reply that answered it, as `{ id, body }`.
 * @returns {Object} The mutation input.
 */
export const buildDuoDecisionResolution = ({ decision, question, answerNote }) => {
  const labels = answerNote ? parseDuoAnswerLabels(answerNote.body).map(squish) : [];
  const offeredLabels = question.options.map(({ label }) => squish(label));
  const selectedOptionIds = (decision.options?.nodes ?? [])
    .filter(({ content }) => labels.includes(squish(content)))
    .map(({ id }) => id);
  const typedLabels = labels.filter((label) => !offeredLabels.includes(label));
  const resolution = { id: decision.id, resolvingNoteId: answerNote?.id ?? null };

  if (typedLabels.length) {
    const content = selectedOptionIds.length
      ? labels.join(', ')
      : stripDuoAnswerMarker(answerNote.body);

    return {
      ...resolution,
      selectedOptionContent: truncate(content, { length: DECISION_TEXT_LENGTH_MAX, omission: '…' }),
    };
  }

  if (selectedOptionIds.length) {
    return { ...resolution, selectedOptionIds, resolutionRationale: null };
  }

  // The API requires a rationale when nothing is selected.
  return {
    ...resolution,
    selectedOptionIds,
    resolutionRationale: s__('WorkItemDecisionLog|The question was resolved without an answer.'),
  };
};

// Decisions have no subscription, and Duo posts its question after the page loads, so the cached
// list may not have the decision yet. The query also stands in for the `decision_log` flag, which
// only the work item pages push to `gon`.
const fetchDuoQuestionDecision = async ({ apolloClient, fullPath, workItemIid, discussionId }) => {
  const { data } = await apolloClient.query({
    query: decisionLogQuery,
    variables: { fullPath, iid: workItemIid },
    fetchPolicy: fetchPolicies.NETWORK_ONLY,
  });

  return data?.namespace?.workItem?.features?.decisionLog?.decisions?.nodes?.find(
    (node) => node.discussionId === discussionId,
  );
};

/**
 * Resolves the open decision the backend created when GitLab Duo posted a clarifying question,
 * once the question's thread is resolved. Questions with no decision, such as those posted before
 * decisions were created for them, are skipped, and so is a decision that is already resolved.
 *
 * @param {Object} params
 * @param {Object} params.apolloClient The Apollo client.
 * @param {string} params.fullPath Full path of the work item's namespace.
 * @param {string} params.workItemIid IID of the work item.
 * @param {string} params.discussionId Global ID of the question's thread.
 * @param {Object} params.questionNote The thread's first note, which carries the question.
 * @param {Array<Object>} [params.replies] The thread's replies, oldest first.
 * @param {Object} [params.answerNote] The reply posted while resolving the thread, if any.
 * @returns {Promise<Object|null>} The resolved decision, or null when nothing was resolved.
 */
export const resolveDuoQuestionDecision = async ({
  apolloClient,
  fullPath,
  workItemIid,
  discussionId,
  questionNote,
  replies = [],
  answerNote,
}) => {
  const parsed = parseDuoQuestion(questionNote?.body);
  if (parsed.status !== PARSE_STATUS_OK) return null;

  const { question } = parsed;

  try {
    const decision = await fetchDuoQuestionDecision({
      apolloClient,
      fullPath,
      workItemIid,
      discussionId,
    });
    if (!decision || decision.resolvedAt) return null;

    const { data: resolveData } = await apolloClient.mutate({
      mutation: resolveDecisionMutation,
      variables: {
        input: buildDuoDecisionResolution({
          decision,
          question,
          answerNote: findDuoAnswerNote({ questionNote, replies, postedReply: answerNote }),
        }),
      },
    });

    const { decision: resolved, errors } = resolveData?.workItemDecisionResolve ?? {};
    if (errors?.length) throw new Error(errors.join(', '));

    return resolved;
  } catch (error) {
    createAlert({
      message: s__(
        'WorkItemDecisionLog|The thread was resolved, but the decision log could not be updated. To try again, reopen the thread and resolve it.',
      ),
      captureError: true,
      error,
    });

    return null;
  }
};

/**
 * The `workItemDecisionUpdate` input that moves a resolved decision to a changed answer. Only
 * options whose pick changes are sent, and the reply that changed it becomes the resolving note.
 *
 * @param {Object} params
 * @param {Object} params.decision The resolved decision from the decision log query.
 * @param {Object} params.answerNote The reply that changed the answer, as `{ id, body }`.
 * @param {string} params.currentUserId Global ID of the user who changed the answer.
 * @returns {Object} The mutation input.
 */
export const buildDuoDecisionUpdate = ({ decision, answerNote, currentUserId }) => {
  const labels = parseDuoAnswerLabels(answerNote.body).map(squish);
  const options = (decision.options?.nodes ?? []).flatMap(({ id, content, selected }) => {
    const isPicked = labels.includes(squish(content));

    return isPicked === selected ? [] : [{ id, selected: isPicked }];
  });

  return {
    id: decision.id,
    resolvingNoteId: answerNote.id,
    resolvedById: currentUserId,
    ...(options.length ? { options } : {}),
  };
};

/**
 * Updates the resolved decision of a question whose answer was changed from its resolved thread.
 * Questions with no decision, or whose decision was never resolved, are skipped.
 *
 * @param {Object} params
 * @param {Object} params.apolloClient The Apollo client.
 * @param {string} params.fullPath Full path of the work item's namespace.
 * @param {string} params.workItemIid IID of the work item.
 * @param {string} params.discussionId Global ID of the question's thread.
 * @param {Object} params.questionNote The thread's first note, which carries the question.
 * @param {Object} params.answerNote The reply that changed the answer, as `{ id, body }`.
 * @param {string} params.currentUserId Global ID of the user who changed the answer.
 * @returns {Promise<Object|null>} The updated decision, or null when nothing was updated.
 */
export const updateDuoQuestionDecision = async ({
  apolloClient,
  fullPath,
  workItemIid,
  discussionId,
  questionNote,
  answerNote,
  currentUserId,
}) => {
  if (parseDuoQuestion(questionNote?.body).status !== PARSE_STATUS_OK) return null;

  try {
    const decision = await fetchDuoQuestionDecision({
      apolloClient,
      fullPath,
      workItemIid,
      discussionId,
    });
    if (!decision?.resolvedAt) return null;

    const { data } = await apolloClient.mutate({
      mutation: updateDecisionMutation,
      variables: { input: buildDuoDecisionUpdate({ decision, answerNote, currentUserId }) },
    });

    const { decision: updated, errors } = data?.workItemDecisionUpdate ?? {};
    if (errors?.length) throw new Error(errors.join(', '));

    return updated;
  } catch (error) {
    createAlert({
      message: s__(
        'WorkItemDecisionLog|Your answer was changed, but the decision log could not be updated. Update the decision from the decision log instead.',
      ),
      captureError: true,
      error,
    });

    return null;
  }
};

/**
 * The `workItemDecisionUpdate` input that rewrites a written-in decision after the reply that
 * resolved it was edited. An answer of offered picks returns null, since its marker rather than
 * its wording decides what was picked. So does a decision that no longer holds the text the
 * reply wrote, such as one changed from the decision log since, so only that text is replaced.
 *
 * @param {Object} params
 * @param {Object} params.decision The resolved decision from the decision log query.
 * @param {Object} params.question The parsed Duo question the decision holds.
 * @param {Object} params.answerNote The edited reply, as `{ id, body }`.
 * @param {string} params.previousBody The reply's body before the edit.
 * @returns {Object|null} The mutation input, or null when the decision should not change.
 */
export const buildDuoDecisionEdit = ({ decision, question, answerNote, previousBody }) => {
  const writtenIn = (body) =>
    buildDuoDecisionResolution({ decision, question, answerNote: { ...answerNote, body } })
      .selectedOptionContent;
  const content = writtenIn(answerNote.body);
  const previousContent = writtenIn(previousBody);
  const selected = (decision.options?.nodes ?? []).filter((option) => option.selected);

  if (!content || !previousContent || squish(content) === squish(previousContent)) return null;
  if (selected.length !== 1 || squish(selected[0].content) !== squish(previousContent)) {
    return null;
  }

  return { id: decision.id, selectedOptionContent: content };
};

/**
 * Keeps a written-in decision in step with the reply that resolved it, once that reply is edited.
 * Replies in threads that are not Duo questions are skipped before anything is fetched.
 *
 * @param {Object} params
 * @param {Object} params.apolloClient The Apollo client.
 * @param {string} params.fullPath Full path of the work item's namespace.
 * @param {string} params.workItemIid IID of the work item.
 * @param {string} params.discussionId Global ID of the question's thread.
 * @param {Object} params.questionNote The thread's first note, which carries the question.
 * @param {Object} params.answerNote The edited reply, as `{ id, body }`.
 * @param {string} params.previousBody The reply's body before the edit.
 * @returns {Promise<Object|null>} The updated decision, or null when nothing was updated.
 */
export const syncDuoQuestionDecision = async ({
  apolloClient,
  fullPath,
  workItemIid,
  discussionId,
  questionNote,
  answerNote,
  previousBody,
}) => {
  const parsed = parseDuoQuestion(questionNote?.body);
  if (parsed.status !== PARSE_STATUS_OK) return null;

  try {
    const decision = await fetchDuoQuestionDecision({
      apolloClient,
      fullPath,
      workItemIid,
      discussionId,
    });
    // Notes come back as `DiscussionNote` IDs, but the decision stores a plain `Note` ID.
    const resolvedByReply =
      getIdFromGraphQLId(decision?.resolvingNoteId) === getIdFromGraphQLId(answerNote.id);
    if (!decision?.resolvedAt || !resolvedByReply) return null;

    const input = buildDuoDecisionEdit({
      decision,
      question: parsed.question,
      answerNote,
      previousBody,
    });
    if (!input) return null;

    const { data } = await apolloClient.mutate({
      mutation: updateDecisionMutation,
      variables: { input },
    });

    const { decision: updated, errors } = data?.workItemDecisionUpdate ?? {};
    if (errors?.length) throw new Error(errors.join(', '));

    return updated;
  } catch (error) {
    createAlert({
      message: s__(
        'WorkItemDecisionLog|Your reply was updated, but the decision log could not be updated. Update the decision from the decision log instead.',
      ),
      captureError: true,
      error,
    });

    return null;
  }
};
