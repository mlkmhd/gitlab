import { s__ } from '~/locale';

export const AGENT_SESSION_INBOX_STATUS_LABELS = {
  INPUT_REQUIRED: s__('DuoAgentsPlatform|Waiting for input'),
  IDLE: s__('DuoAgentPlatform|Idle'),
  PLAN_APPROVAL_REQUIRED: s__('DuoAgentPlatform|Approve plan'),
  TOOL_CALL_APPROVAL_REQUIRED: s__('DuoAgentsPlatform|Confirm action'),
  STOPPED: s__('DuoAgentPlatform|Canceled'),
};

export const AGENT_SESSION_INBOX_ACTION_STATUSES = [
  'PLAN_APPROVAL_REQUIRED',
  'TOOL_CALL_APPROVAL_REQUIRED',
];
