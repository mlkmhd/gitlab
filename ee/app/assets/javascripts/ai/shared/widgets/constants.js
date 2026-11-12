import { s__ } from '~/locale';
import {
  AGENT_SESSION_AWAITING_INPUT_LABEL,
  WORKFLOW_AWAITING_INPUT_STATUSES,
} from 'ee/ai/duo_agents_platform/constants';

export const SESSION_AWAITING_INPUT_GROUP = {
  statuses: WORKFLOW_AWAITING_INPUT_STATUSES,
  title: AGENT_SESSION_AWAITING_INPUT_LABEL,
};

export const SESSION_OTHER_GROUPS = [
  { statuses: ['RUNNING'], title: s__('DuoAgentPlatform|Running') },
  { statuses: ['IDLE'], title: s__('DuoAgentPlatform|Idle') },
  { statuses: ['PAUSED'], title: s__('DuoAgentPlatform|Paused') },
  { statuses: ['FAILED'], title: s__('DuoAgentPlatform|Failed') },
  { statuses: ['CREATED'], title: s__('DuoAgentPlatform|Created') },
  { statuses: ['FINISHED'], title: s__('DuoAgentPlatform|Finished') },
  { statuses: ['STOPPED'], title: s__('DuoAgentPlatform|Canceled') },
];

export const AGENT_SESSIONS_POLL_INTERVAL = 30000;
// Passed explicitly by both the sessions query and its subscription: the pushed frame
// only updates the list if it writes the same cache field key the query reads.
export const AGENT_SESSIONS_PAGE_SIZE = 20;

export const AWAITING_INPUT_HEADER_BG_CLASS = 'gl-bg-feedback-warning';
export const OTHER_GROUP_HEADER_BG_CLASS = 'gl-bg-subtle';

// Values of the DuoWorkflowTriggerSource GraphQL enum: what started a session.
export const SESSION_TRIGGER_SOURCE_HUMAN = 'HUMAN';
export const SESSION_TRIGGER_SOURCE_SCHEDULED = 'SCHEDULED';
export const SESSION_TRIGGER_SOURCE_FLOW = 'FLOW';
export const SESSION_TRIGGER_SOURCE_VERIFICATION = 'VERIFICATION';
export const SESSION_TRIGGER_SOURCE_SYSTEM = 'SYSTEM';
