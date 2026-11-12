import { maxBy } from 'lodash-es';
import { n__, sprintf } from '~/locale';
import { objectToQuery } from '~/lib/utils/url_utility';
import { InternalEvents } from '~/tracking';
import { DETAIL_VIEW_QUERY_PARAM_NAME } from '~/work_items/constants';
import { DUO_WORKFLOW_DEVELOPER_DEFINITION } from 'ee/ai/constants';
import {
  AGENT_STEP_PILL_VARIANTS,
  READINESS_SCORE_MIN,
  READINESS_SCORE_MAX,
  WORKPLAN_PANEL_URL_VALUE,
  WORKPLAN_STATE_PARAM,
  WORKPLAN_STATE_EDIT,
} from './constants';

export const getVariantColor = (variant) =>
  AGENT_STEP_PILL_VARIANTS[variant] ?? AGENT_STEP_PILL_VARIANTS.placeholder;

export const getAwaitingInputLabel = (count) =>
  sprintf(
    n__(
      'AgentPlan|Awaiting input (%{count} question)',
      'AgentPlan|Awaiting input (%{count} questions)',
      count,
    ),
    { count },
  );

export const isValidReadinessScore = (score) =>
  score === null ||
  (Number.isInteger(score) && score >= READINESS_SCORE_MIN && score <= READINESS_SCORE_MAX);

export const trackWorkplanImplement = (surface, readinessScore) => {
  InternalEvents.trackEvent('click_work_item_workplan_implement', {
    property: surface,
    ...(Number.isFinite(readinessScore) && { value: readinessScore }),
  });
};

export const buildWorkplanQuery = ({ editing = false } = {}) => ({
  [DETAIL_VIEW_QUERY_PARAM_NAME]: WORKPLAN_PANEL_URL_VALUE,
  ...(editing && { [WORKPLAN_STATE_PARAM]: WORKPLAN_STATE_EDIT }),
});

// workItemWebUrl is relative, so build the query string directly rather than
// through setUrlParams, which cannot parse a relative URL.
export const buildWorkplanPageUrl = (base, { editing = false } = {}) =>
  `${base}?${objectToQuery(buildWorkplanQuery({ editing }))}`;

export const trackWorkplanCreateManually = (surface) => {
  InternalEvents.trackEvent('click_work_item_workplan_create_manually', { property: surface });
};

export const isDeveloperSession = (session) =>
  session?.workflowDefinition === DUO_WORKFLOW_DEVELOPER_DEFINITION;

export const getLatestDeveloperSession = (sessions = []) =>
  maxBy(
    sessions.filter((session) => isDeveloperSession(session)),
    (session) => Date.parse(session.createdAt),
  );
