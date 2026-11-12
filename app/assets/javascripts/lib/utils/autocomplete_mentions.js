import { sortBy } from 'lodash-es';

// Mirrors Gitlab::PathRegex::NAMESPACE_FORMAT_REGEX_JS (lib/gitlab/path_regex.rb),
// the JS-compatible username/namespace pattern GitLab uses for client-side
// username validation. Keep in sync with that constant. The `255` bound is
// Namespace::URL_MAX_LENGTH; usernames may contain dots/hyphens internally but
// cannot end with a dot.
const NAMESPACE_FORMAT_REGEX_JS = '[a-zA-Z0-9_.][a-zA-Z0-9_.-]{0,254}[a-zA-Z0-9_-]|[a-zA-Z0-9_]';

// Matches `@username` mentions in editor text. The leading boundary avoids
// matching the `@` inside email addresses (e.g. `user@example.com`); we use a
// boundary rather than a lookbehind to follow GitLab's lookbehind-free FE
// regex convention (see NAMESPACE_FORMAT_REGEX_JS above).
const USERNAME_MENTION_REGEX = new RegExp(`(?:^|[^\\w@])@(${NAMESPACE_FORMAT_REGEX_JS})`, 'g');

// Matches fenced (``` / ~~~) and inline (`...`) code spans so they can be
// removed before scanning; a mention inside code is not a real mention. This
// approximates the Banzai pipeline's code handling, which the plain markdown
// textarea has no structured equivalent for.
//
// Every alternative uses a fixed delimiter or a negated class, never a
// variable-length backreference, so matching stays linear. A pattern like
// `(`+)[\s\S]*?\1` backtracks in O(n^2) on a long run of unmatched backticks,
// which would freeze the editor because this runs over the whole input on each
// keystroke of the quick-action dropdown. The trade-off is that multi-backtick
// inline spans (``...``) are not stripped as a single span, an acceptable miss
// for an ordering heuristic.
const CODE_REGEX = /```[\s\S]*?```|~~~[\s\S]*?~~~|`[^`\n]*`/g;

/**
 * Extracts the usernames already mentioned in a block of editor text.
 *
 * @param {String} text - Markdown/plain text content of the editor.
 * @returns {String[]} Unique, lower-cased usernames found in the text.
 */
export function extractMentionedUsernames(text) {
  if (!text) return [];

  const withoutCode = text.replace(CODE_REGEX, ' ');

  const usernames = new Set();
  for (const [, username] of withoutCode.matchAll(USERNAME_MENTION_REGEX)) {
    usernames.add(username.toLowerCase());
  }

  return [...usernames];
}

/**
 * Reorders a list of member autocomplete items so that members already
 * mentioned in the editor float to the top, ordered by where their mention
 * first appears in the text. Non-mentioned members keep their incoming order.
 *
 * @param {Array<{username: String}>} members - Already-filtered member items.
 * @param {String[]} mentionedUsernames - Usernames in order of appearance.
 * @returns {Array} Reordered member items.
 */
export function prioritizeMentionedMembers(members, mentionedUsernames) {
  if (!mentionedUsernames?.length) return members;

  const order = new Map(
    mentionedUsernames.map((username, index) => [username.toLowerCase(), index]),
  );
  const rankOf = (member) => order.get(member?.username?.toLowerCase());

  const mentioned = members
    .filter((member) => rankOf(member) !== undefined)
    .sort((a, b) => rankOf(a) - rankOf(b));
  const rest = members.filter((member) => rankOf(member) === undefined);

  return [...mentioned, ...rest];
}

// One short of the 10 listed `@` suggestions, so the issue or merge request
// author, who leads the backend order, is still listed after the thread.
const MAX_THREAD_PARTICIPANTS = 9;

/**
 * Lists the authors of a thread's notes, most recent first, so they can be
 * boosted in `@` suggestions when replying. The current user is left out. Long
 * threads keep the most recent authors and the one who started the thread.
 *
 * @param {Array<{username: String}>} authors - Note authors in thread order.
 * @returns {String[]} Unique, lower-cased usernames.
 */
export function threadParticipantUsernames(authors) {
  const currentUsername = window.gon?.current_username?.toLowerCase();
  const usernames = authors
    .map((author) => author?.username?.toLowerCase())
    .filter((username) => username && username !== currentUsername);
  const unique = [...new Set([...usernames].reverse())];
  if (unique.length <= MAX_THREAD_PARTICIPANTS) return unique;

  const recent = unique.slice(0, MAX_THREAD_PARTICIPANTS - 1);
  const starter = usernames[0];
  const last = recent.includes(starter) ? unique[MAX_THREAD_PARTICIPANTS - 1] : starter;
  return [...recent, last];
}

/**
 * Moves the signed-in user after the other members of the same match tier, so
 * plain `@` mentions lead with the people you are likely to mention.
 *
 * @param {Array<{username: String}>} members - Already-sorted member items.
 * @param {Function} tierOf - Returns the match tier of a member; lower sorts first.
 * @returns {Array} Reordered member items.
 */
export function demoteCurrentUser(members, tierOf = () => 0) {
  const username = window.gon?.current_username?.toLowerCase();
  const isCurrentUser = (member) => member?.username?.toLowerCase() === username;
  if (!username || !members.some((member) => isCurrentUser(member))) return members;

  return sortBy(members, [tierOf, (member) => (isCurrentUser(member) ? 1 : 0)]);
}
