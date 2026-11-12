import codexLogo from 'ee_images/agent_logos/codex.svg?url';
import cursorLogo from 'ee_images/agent_logos/cursor.svg?url';
import cursorDarkLogo from 'ee_images/agent_logos/cursor-dark.svg?url';
import { darkModeEnabled } from '~/lib/utils/color_utils';
import { nDaysBefore, toISODateFormat } from '~/lib/utils/datetime_utility';
import { humanize } from '~/lib/utils/text_utility';
import { objectToQuery } from '~/lib/utils/url_utility';
import { s__, sprintf } from '~/locale';
import {
  AGENT_CLASS_ALL,
  AGENT_TYPE_LABELS,
  SESSION_SOURCE_LABELS,
  TIMEFRAME_LAST_SEVEN_DAYS,
  TIMEFRAME_LAST_THIRTY_DAYS,
} from './constants';

const TIMEFRAME_DAYS = {
  [TIMEFRAME_LAST_SEVEN_DAYS]: 7,
  [TIMEFRAME_LAST_THIRTY_DAYS]: 30,
};

/**
 * Returns the product name of an external agent type, such as `claude-code`.
 *
 * @param {string} agentType - The `agent_type` the backend stores.
 * @returns {string}
 */
export function formatAgentType(agentType) {
  return AGENT_TYPE_LABELS[agentType] || humanize(agentType, '-');
}

// Official brand marks, unaltered, keyed like AGENT_TYPE_LABELS. Only agents
// whose owners approved the use of their mark get an entry, and only in the
// color modes the brand supplies a mark for. Everything else keeps its current
// icon.
//
// `class` enlarges a mark whose file has empty space around it, so its visible
// ink matches the other 16px icons. The file itself stays unaltered. OpenAI's
// Blossom fills about 70% of its canvas, so 16px draws an 11px mark.
const AGENT_TYPE_LOGOS = {
  codex: { light: codexLogo, class: 'gl-scale-150' },
  cursor: { light: cursorLogo, dark: cursorDarkLogo },
};

/**
 * Returns the logo URL of an external agent type for the current color mode, or
 * null when there is no logo for it.
 *
 * @param {string|null} agentType - The `agent_type` the backend stores.
 * @returns {string|null}
 */
export function agentLogo(agentType) {
  const logo = AGENT_TYPE_LOGOS[agentType];
  if (!logo) return null;

  return (darkModeEnabled() ? logo.dark : logo.light) ?? null;
}

/**
 * Returns the class that sizes an agent logo's visible mark like the other
 * 16px icons, or null when the logo needs none. It is a transform, so it keeps
 * the 16px layout box and the row's text and height don't move.
 *
 * @param {string|null} agentType - The `agent_type` the backend stores.
 * @returns {string|null}
 */
export function agentLogoClass(agentType) {
  return AGENT_TYPE_LOGOS[agentType]?.class ?? null;
}

/**
 * Returns the label of a session's source, or undefined for an unknown source.
 *
 * glab records every session with the `CLAUDE_CODE_GLAB` source, whichever agent
 * ran it, so a glab session is named after its agent type instead.
 *
 * @param {Object} session - A session with `source` and `agentType`.
 * @returns {string|undefined}
 */
export function formatSessionSource(session) {
  const { source, agentType } = session || {};

  if (source === 'CLAUDE_CODE_GLAB' && agentType) {
    return sprintf(s__('AiGovernance|%{agent} (glab)'), {
      agent: formatAgentType(agentType),
    });
  }

  return SESSION_SOURCE_LABELS[source];
}

/**
 * Returns the Audit events filters for the given card filters, limited to the
 * dashboard's timeframe and agent class so they match the sessions a card counted.
 *
 * The window starts at the beginning of the UTC day, as the backend's
 * `Ai::Governance::MetricsTimeframe` does, and runs up to now.
 *
 * @param {string} timeframe - An `AiGovernanceMetricsTimeframe` value.
 * @param {Object} filters - Audit events filter tokens, keyed by token type.
 *   An `agentClass` of `ALL` is left out, since Audit events shows every class by default.
 * @returns {Object}
 */
export function auditEventsFilters(timeframe, { agentClass, ...filters } = {}) {
  const params = { ...filters };
  const days = TIMEFRAME_DAYS[timeframe];

  if (agentClass && agentClass !== AGENT_CLASS_ALL) {
    params.agentClass = agentClass;
  }

  if (days) {
    params.startTimeAfter = toISODateFormat(nDaysBefore(new Date(), days, { utc: true }), true);
  }

  return params;
}

/**
 * Returns a link to the Audit events tab with the filters from `auditEventsFilters`.
 *
 * @param {string} timeframe - An `AiGovernanceMetricsTimeframe` value.
 * @param {Object} filters - Audit events filter tokens, keyed by token type.
 * @returns {string}
 */
export function auditEventsHref(timeframe, filters) {
  return `?${objectToQuery({ tab: 'agent-artifacts', ...auditEventsFilters(timeframe, filters) })}`;
}

const SKILLGUARD_VERDICT_PATTERN = /^\s*([a-z_-]+)(?:\s*\(confidence:\s*([\d.]+)\))?/i;
const SKILLGUARD_RISK_SCORE_PATTERN = /^\s*(\d+)(?:\s*\(([A-Z_]+)\))?/;

const skillguardListValues = (item) =>
  (item?.value?.items || []).map((entry) => entry?.value).filter(Boolean);

/**
 * Reads what the SkillGuard analyzer writes into a finding's `details` (its report converter,
 * `report/gitlab/convert.go`): a `verdict` text such as "malicious (confidence: 0.98)", `checked_facts`
 * with the risk flags and a risk score such as "95 (DO_NOT_INSTALL)", and `kept_findings`, one titled
 * entry per problem the analyzer confirmed. Anything missing comes back empty.
 *
 * @param {Array} details - The vulnerability's `details` from GraphQL.
 * @returns {{ verdict: ?string, confidence: ?number, riskScore: ?number, riskBand: ?string,
 *   riskFlags: string[], findings: string[] }}
 */
export function parseSkillguardDetails(details = []) {
  const byField = Object.fromEntries(
    (details || [])
      .filter((detail) => detail?.fieldName)
      .map((detail) => [detail.fieldName, detail]),
  );
  const facts = Object.fromEntries(
    (byField.checked_facts?.items || []).map((item) => [item.fieldName, item]),
  );
  const [, verdict, confidence] = byField.verdict?.value?.match(SKILLGUARD_VERDICT_PATTERN) || [];
  const [, riskScore, riskBand] =
    facts.risk_score?.value?.value?.match(SKILLGUARD_RISK_SCORE_PATTERN) || [];

  return {
    verdict: verdict?.toLowerCase() || null,
    confidence: confidence ? Number(confidence) : null,
    riskScore: riskScore ? Number(riskScore) : null,
    riskBand: riskBand || null,
    riskFlags: skillguardListValues(facts.risk_flags),
    findings: (byField.kept_findings?.items || []).map((item) => item.name).filter(Boolean),
  };
}
