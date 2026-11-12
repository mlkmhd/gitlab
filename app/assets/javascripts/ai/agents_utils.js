import { s__ } from '~/locale';
import { convertObjectPropsToCamelCase } from '~/lib/utils/common_utils';
import { FLOW_TRIGGER_EVENTS } from '~/vue_shared/constants';

const extractDisabled = (user) => {
  return Boolean(user?.duoStatus?.disabled ?? user?.disabled);
};

const extractDisabledReason = (user) => {
  return user?.duoStatus?.disabledReason ?? user?.disabledReason ?? user?.disabled_reason;
};

const extractFlowTriggerEvents = (user) => {
  return (
    user?.duoStatus?.flowTriggerEvents ?? user?.flowTriggerEvents ?? user?.flow_trigger_events ?? []
  );
};

const extractCompositeIdentityEnforced = (user) => {
  return user?.compositeIdentityEnforced ?? user?.composite_identity_enforced;
};

export const userIsAgent = (user) => {
  return Boolean(extractCompositeIdentityEnforced(user));
};

export const userHasFlowTriggerEvent = (user, eventType) => {
  const flowTriggerEvents = extractFlowTriggerEvents(user);

  return flowTriggerEvents.includes(eventType);
};

export const userDisabledReason = (user, eventType) => {
  const disabled = extractDisabled(user);
  const disabledReason = extractDisabledReason(user);
  const hasFlowTriggers = userHasFlowTriggerEvent(user, eventType);
  const isAgent = userIsAgent(user);

  if (disabled) {
    return disabledReason || s__('Agents|Cannot be assigned');
  }

  if (!isAgent) {
    return null;
  }

  if (!hasFlowTriggers) {
    return s__('Agents|No triggers for this event');
  }

  return null;
};

export const userIsDisabled = (user, eventType) => {
  return Boolean(userDisabledReason(user, eventType));
};

/* eslint-disable @gitlab/no-hardcoded-urls -- quick action command strings, not URLs */
const FLOW_TRIGGER_EVENT_BY_COMMAND = new Map([
  ['/assign', FLOW_TRIGGER_EVENTS.ASSIGN],
  ['/reassign', FLOW_TRIGGER_EVENTS.ASSIGN],
  ['/assign_reviewer', FLOW_TRIGGER_EVENTS.ASSIGN_REVIEWER],
  ['/reviewer', FLOW_TRIGGER_EVENTS.ASSIGN_REVIEWER],
  ['/request_review', FLOW_TRIGGER_EVENTS.ASSIGN_REVIEWER],
  ['/reassign_reviewer', FLOW_TRIGGER_EVENTS.ASSIGN_REVIEWER],
]);
const REMOVAL_COMMANDS = ['/unassign', '/unassign_reviewer', '/remove_reviewer'];
/* eslint-enable @gitlab/no-hardcoded-urls */

// Returns undefined for commands that don't map to a flow trigger event.
export const flowTriggerEventForCommand = (command) => FLOW_TRIGGER_EVENT_BY_COMMAND.get(command);

// Removal commands must list everyone currently assigned, whatever their agent status.
export const isRemovalCommand = (command) => REMOVAL_COMMANDS.includes(command);

export const userDisabledAttributes = (user, eventType) => {
  const reason = userDisabledReason(user, eventType);

  if (reason) {
    return {
      isDisabled: true,
      disabledReason: reason,
    };
  }

  return {
    isDisabled: false,
  };
};

export const parseAgentPresence = (presence) => {
  if (!presence) return null;

  const parsed = convertObjectPropsToCamelCase(presence, { deep: true });
  return parsed.agentName && parsed.sessionId ? parsed : null;
};
