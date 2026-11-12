import { SESSION_TRIGGER_SOURCE_HUMAN } from 'ee/ai/shared/widgets/constants';

export const mockAgentActorLinePropsWithoutAgentName = {
  sessionId: 'gid://gitlab/Ai::DuoWorkflows::Workflow/42',
  canViewSession: true,
  triggerSource: SESSION_TRIGGER_SOURCE_HUMAN,
  user: { id: 'gid://gitlab/User/7', username: 'nokafor', webPath: '/nokafor' },
};

export const mockAgentActorLineProps = {
  ...mockAgentActorLinePropsWithoutAgentName,
  agentName: 'Developer Agent',
  withAgentName: true,
};

export const mockAgentPresence = {
  agentName: 'Developer Agent',
  agentCatalogWebPath: '/-/ai/catalog/agents/3',
  sessionId: 'gid://gitlab/Ai::DuoWorkflows::Workflow/42',
  triggerSource: SESSION_TRIGGER_SOURCE_HUMAN,
  user: { id: 'gid://gitlab/User/7', username: 'nokafor', webPath: '/nokafor' },
  userPermissions: { readDuoWorkflow: true },
};
