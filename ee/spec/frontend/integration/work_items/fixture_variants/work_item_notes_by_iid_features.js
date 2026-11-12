import workItemNotesByIidFeaturesBase from 'test_fixtures/graphql/work_items/integration/work_item_notes_by_iid_features.query.graphql.json';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData } from 'ee_jest/integration/core/fixture_utils';
import { AGENT_CREATED_SESSION } from '../fixtures_helper';

const DUO_QUESTION_BODY = `Should over-limit requests be rejected or throttled?

\`\`\`json:duo-question
${JSON.stringify({
  type: 'closed',
  question: 'Reject or throttle over-limit requests?',
  options: [
    { id: 'reject', label: 'Reject immediately', recommended: true },
    { id: 'throttle', label: 'Throttle' },
  ],
})}
\`\`\``;

const DISCUSSION_PATH = 'namespace.workItem.features.notes.discussions.nodes[0]';
export const OTHER_USER_ID = 'gid://gitlab/User/999999';
const NOTE_AWARD_PERMISSION_PATH = `${DISCUSSION_PATH}.notes.nodes[0].userPermissions.awardEmoji`;

// The fixture's only thread, turned into an open Duo question the viewer can resolve.
const withDuoQuestion = (fixture) =>
  [
    [`${DISCUSSION_PATH}.notes.nodes[0].body`, DUO_QUESTION_BODY],
    [`${DISCUSSION_PATH}.resolvable`, true],
    [`${DISCUSSION_PATH}.userPermissions.resolveNote`, true],
  ].reduce((variant, [path, value]) => setFixtureData(variant, { path }, value), fixture);

export default defineFixtureVariants({
  query: 'workItemNotesByIidFeatures',
  variants: {
    BASE: workItemNotesByIidFeaturesBase,
    // Path selector, not a key walk: awardEmoji also names the reaction connection
    // on the same note, so a first-match walk would blank the reactions instead.
    NO_AWARD_PERMISSION: setFixtureData(
      workItemNotesByIidFeaturesBase,
      { path: NOTE_AWARD_PERMISSION_PATH },
      false,
    ),
    DUO_QUESTION: withDuoQuestion(workItemNotesByIidFeaturesBase),
    POSTED_BY_AGENT_SESSION: setFixtureData(
      workItemNotesByIidFeaturesBase,
      { path: `${DISCUSSION_PATH}.notes.nodes[0].duoCreatedSession` },
      AGENT_CREATED_SESSION,
    ),
    // The recorded note is by the signed-in user, who can't report their own comment.
    POSTED_BY_OTHER_USER: setFixtureData(
      workItemNotesByIidFeaturesBase,
      { path: `${DISCUSSION_PATH}.notes.nodes[0].author.id` },
      OTHER_USER_ID,
    ),
  },
});
