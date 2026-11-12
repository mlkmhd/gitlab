import { s__, sprintf } from '~/locale';
import { humanize } from '~/lib/utils/text_utility';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { formatAgentDefinition } from 'ee/ai/duo_agents_platform/utils';
import { formatSessionSource } from 'ee/ai/governance/utils';
import { CLIENT_TYPES, DEFAULT_CLIENT_TYPE, MCP_CLIENT_TYPE } from './constants';

/**
 * Maps a `duoWorkflowSessionArtifacts` node onto the `aiGovernanceSessions`
 * shape, so components only handle one shape whichever API the flag selects.
 *
 * @param {Object} node - A DuoWorkflowSessionArtifact node.
 * @returns {Object}
 */
export function normalizeLegacySession(node) {
  return {
    ...node,
    flowType: node.workflowDefinition,
    sessionStartedAt: node.workflowCreatedAt,
    sessionId: String(getIdFromGraphQLId(node.id)),
  };
}

/**
 * Returns the display name of a session. External sessions can have no flow
 * type, so their source names them instead.
 *
 * @param {Object} item - A session item.
 * @returns {string}
 */
export function formatSessionName(item) {
  const sourceLabel = formatSessionSource(item);

  if (!item?.flowType && sourceLabel) {
    return sourceLabel;
  }

  return formatAgentDefinition(item?.flowType);
}

/**
 * Converts a snake_case audit event name into a human-readable title.
 *
 * Examples:
 *   'ai_agent_session_ended'   => 'Agent session ended'
 *   'ai_llm_input_sent'        => 'Llm input sent'
 *   'ai_tool_invoked'          => 'Tool invoked'
 *
 * @param {string} name - The raw event name from the API.
 * @returns {string}
 */
export function formatEventName(name) {
  if (!name) return '';
  return name
    .replace(/^ai_/, '')
    .replace(/_/g, ' ')
    .replace(/^./, (c) => c.toUpperCase());
}

/**
 * Returns the client type object for a session artifact item.
 *
 * `agentType` is null for sessions run on the GitLab Duo Agent Platform and a
 * raw value like `claude-code` for external agents. Unknown values are
 * humanised so the report never misattributes a session to GitLab Duo.
 * MCP sessions without a recognised agent type are the GitLab MCP server itself.
 *
 * @param {Object} item - A session artifact item.
 * @returns {{ name: string, icon?: string }}
 */
export function getClientType(item) {
  if (item.source === 'MCP' && (!item.agentType || item.agentType === 'unknown')) {
    return MCP_CLIENT_TYPE;
  }

  if (!item.agentType) {
    return DEFAULT_CLIENT_TYPE;
  }

  return CLIENT_TYPES[item.agentType] || { name: humanize(item.agentType, '-') };
}

const LINK_TYPE_CREATED = 'CREATED';
const STARTED_FROM_LINK_TYPES = ['SOURCE', 'TRIGGERED'];

// Rendered as text, so the author name must not be HTML-escaped.
const formatNoteTitle = (note) =>
  note.author?.name
    ? sprintf(s__('AgentArtifacts|Comment by %{author}'), { author: note.author.name }, false)
    : s__('AgentArtifacts|Comment');

const toLinkEntries = (connection, kind, toEntry) =>
  (connection?.nodes ?? [])
    .map((link) => ({ linkType: link.linkType, item: link[kind] }))
    .filter(({ item }) => Boolean(item))
    .map(({ linkType, item }) => ({ linkType, kind, ...toEntry(item) }));

/**
 * Groups the merge request, note, and work item links of an AI governance
 * session into the items it was started from and the items it created.
 * Links to items the current user can't read have a `null` item and are left out.
 * `hasMore` is true when any connection has more links than were fetched.
 *
 * @param {Object} session - An AiGovernanceSession node with its link connections.
 * @returns {{ startedFrom: Array<Object>, created: Array<Object>, hasMore: boolean }}
 */
export function groupSessionLinks(session) {
  const entries = [
    ...toLinkEntries(session?.mergeRequestLinks, 'mergeRequest', (mergeRequest) => ({
      id: mergeRequest.id,
      title: mergeRequest.title,
      reference: mergeRequest.reference,
      url: mergeRequest.webPath,
    })),
    ...toLinkEntries(session?.workItemLinks, 'workItem', (workItem) => ({
      id: workItem.id,
      title: workItem.title,
      reference: workItem.reference,
      url: workItem.webPath,
      workItemType: {
        name: workItem.workItemType?.name,
        iconName: workItem.workItemType?.iconName,
      },
    })),
    ...toLinkEntries(session?.noteLinks, 'note', (note) => ({
      id: note.id,
      title: formatNoteTitle(note),
      reference: null,
      url: note.url,
    })),
  ];

  const withLinkType = (matches) =>
    entries.filter(({ linkType }) => matches(linkType)).map(({ linkType, ...entry }) => entry);

  return {
    startedFrom: withLinkType((linkType) => STARTED_FROM_LINK_TYPES.includes(linkType)),
    created: withLinkType((linkType) => linkType === LINK_TYPE_CREATED),
    hasMore: [session?.mergeRequestLinks, session?.workItemLinks, session?.noteLinks].some(
      (connection) => connection?.pageInfo?.hasNextPage === true,
    ),
  };
}

/**
 * Moves focus into a side panel. The panel is focusable only until focus leaves it again,
 * as in the redirect_scroll_keys_to_panel directive, so a click inside never lands on it.
 *
 * @param {HTMLElement} element - The panel's root element.
 */
export function focusPanel(element) {
  if (!element) return;

  if (!element.hasAttribute('tabindex')) {
    element.setAttribute('tabindex', '-1');
    element.addEventListener('blur', () => element.removeAttribute('tabindex'), { once: true });
  }

  element.focus();
}
