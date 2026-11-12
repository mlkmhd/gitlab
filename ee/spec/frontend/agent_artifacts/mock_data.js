export const mockUser = {
  id: 'gid://gitlab/User/1',
  name: 'Alice Smith',
  username: 'alice',
  avatarUrl: '/uploads/-/system/user/avatar/1/avatar.png',
  webPath: '/alice',
  __typename: 'UserCore',
};

export const mockArtifactNodes = [
  {
    id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1908',
    workflowDefinition: 'false_positive_detection/v1',
    agentType: null,
    webPath: '/gitlab-org/security-scanner/-/automate/agent-sessions/1908',
    downloadPath: '/gitlab-org/security-scanner/-/security/agent_artifacts/1908/download',
    auditEventsCount: 4,
    workflowCreatedAt: '2026-03-05T22:14:17Z',
    project: {
      id: 'gid://gitlab/Project/278964',
      name: 'Security Scanner',
      webPath: '/gitlab-org/security-scanner',
      fullPath: 'gitlab-org/security-scanner',
      __typename: 'Project',
    },
    triggeredBy: mockUser,
    __typename: 'DuoWorkflowSessionArtifact',
  },
  {
    id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1909',
    workflowDefinition: 'code_review/v1',
    agentType: 'claude-code',
    webPath: '/gitlab-org/frontend-app/-/automate/agent-sessions/1909',
    downloadPath: '/gitlab-org/frontend-app/-/security/agent_artifacts/1909/download',
    auditEventsCount: 7,
    workflowCreatedAt: '2026-03-05T21:30:45Z',
    project: {
      id: 'gid://gitlab/Project/278965',
      name: 'Frontend App',
      webPath: '/gitlab-org/frontend-app',
      fullPath: 'gitlab-org/frontend-app',
      __typename: 'Project',
    },
    triggeredBy: mockUser,
    __typename: 'DuoWorkflowSessionArtifact',
  },
];

export const mockArtifactNodeNoWebPath = {
  id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1910',
  workflowDefinition: 'code_review/v1',
  agentType: null,
  webPath: null,
  downloadPath: null,
  auditEventsCount: 2,
  workflowCreatedAt: '2026-03-06T10:00:00Z',
  project: null,
  triggeredBy: null,
  __typename: 'DuoWorkflowSessionArtifact',
};

export const mockPageInfo = {
  startCursor: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1908',
  endCursor: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1909',
  hasNextPage: true,
  hasPreviousPage: false,
  __typename: 'PageInfo',
};

export const mockAgentArtifactsResponse = {
  data: {
    group: {
      id: 'gid://gitlab/Group/1',
      duoWorkflowSessionArtifacts: {
        count: 2,
        nodes: mockArtifactNodes,
        pageInfo: mockPageInfo,
        __typename: 'DuoWorkflowSessionArtifactConnection',
      },
      __typename: 'Group',
    },
  },
};

export const mockProjectAgentArtifactsResponse = {
  data: {
    project: {
      id: 'gid://gitlab/Project/1',
      duoWorkflowSessionArtifacts: {
        count: 2,
        nodes: mockArtifactNodes,
        pageInfo: mockPageInfo,
        __typename: 'DuoWorkflowSessionArtifactConnection',
      },
      __typename: 'Project',
    },
  },
};

export const mockEmptyAgentArtifactsResponse = {
  data: {
    group: {
      id: 'gid://gitlab/Group/1',
      duoWorkflowSessionArtifacts: {
        count: 0,
        nodes: [],
        pageInfo: {
          startCursor: null,
          endCursor: null,
          hasNextPage: false,
          hasPreviousPage: false,
          __typename: 'PageInfo',
        },
        __typename: 'DuoWorkflowSessionArtifactConnection',
      },
      __typename: 'Group',
    },
  },
};

export const mockGitlabDuoSessionNode = {
  id: 'gid://gitlab/Ai::Governance::Session/501',
  sessionId: '1908',
  source: 'GITLAB_DUO',
  flowType: 'false_positive_detection/v1',
  agentType: null,
  webPath: '/gitlab-org/security-scanner/-/automate/agent-sessions/1908',
  downloadPath: '/gitlab-org/security-scanner/-/security/agent_artifacts/1908/download',
  sessionStartedAt: '2026-03-05T22:14:17Z',
  auditEventsCount: 4,
  project: mockArtifactNodes[0].project,
  triggeredBy: mockUser,
  __typename: 'AiGovernanceSession',
};

export const mockClaudeCodeSessionNode = {
  id: 'gid://gitlab/Ai::Governance::Session/502',
  sessionId: '3f2b1c9e-6a7d-4e1f-9b2a-0c8d7e6f5a4b',
  source: 'CLAUDE_CODE_GLAB',
  flowType: null,
  agentType: 'claude-code',
  webPath: null,
  downloadPath: null,
  sessionStartedAt: '2026-03-05T21:30:45Z',
  auditEventsCount: 3,
  project: mockArtifactNodes[1].project,
  triggeredBy: mockUser,
  __typename: 'AiGovernanceSession',
};

export const mockSessionNodes = [mockGitlabDuoSessionNode, mockClaudeCodeSessionNode];

const buildSessionsConnection = (nodes) => ({
  nodes,
  pageInfo: mockPageInfo,
  __typename: 'AiGovernanceSessionConnection',
});

export const mockAiGovernanceSessionsResponse = {
  data: {
    group: {
      id: 'gid://gitlab/Group/1',
      aiGovernanceSessions: buildSessionsConnection(mockSessionNodes),
      __typename: 'Group',
    },
  },
};

export const mockProjectAiGovernanceSessionsResponse = {
  data: {
    project: {
      id: 'gid://gitlab/Project/1',
      aiGovernanceSessions: buildSessionsConnection(mockSessionNodes),
      __typename: 'Project',
    },
  },
};

export const buildLinkConnection = (typename, nodes = [], hasNextPage = false) => ({
  nodes,
  pageInfo: { hasNextPage, __typename: 'PageInfo' },
  __typename: typename,
});

export const mockSessionLinksNode = {
  id: 'gid://gitlab/Ai::Governance::Session/501',
  mergeRequestLinks: buildLinkConnection('AiGovernanceSessionMergeRequestLinkConnection', [
    {
      id: 'gid://gitlab/Ai::DuoWorkflows::WorkflowMergeRequest/1',
      linkType: 'SOURCE',
      mergeRequest: {
        id: 'gid://gitlab/MergeRequest/11',
        title: 'Source merge request',
        reference: '!11',
        webPath: '/gitlab-org/security-scanner/-/merge_requests/11',
        __typename: 'MergeRequest',
      },
      __typename: 'AiGovernanceSessionMergeRequestLink',
    },
    {
      id: 'gid://gitlab/Ai::DuoWorkflows::WorkflowMergeRequest/2',
      linkType: 'CREATED',
      mergeRequest: {
        id: 'gid://gitlab/MergeRequest/12',
        title: 'Created merge request',
        reference: '!12',
        webPath: '/gitlab-org/security-scanner/-/merge_requests/12',
        __typename: 'MergeRequest',
      },
      __typename: 'AiGovernanceSessionMergeRequestLink',
    },
    {
      id: 'gid://gitlab/Ai::DuoWorkflows::WorkflowMergeRequest/3',
      linkType: 'CREATED',
      mergeRequest: null,
      __typename: 'AiGovernanceSessionMergeRequestLink',
    },
  ]),
  noteLinks: buildLinkConnection('AiGovernanceSessionNoteLinkConnection', [
    {
      id: 'gid://gitlab/Ai::DuoWorkflows::WorkflowNote/1',
      linkType: 'TRIGGERED',
      note: {
        id: 'gid://gitlab/Note/21',
        url: 'http://gdk.test/gitlab-org/security-scanner/-/merge_requests/11#note_21',
        author: { id: 'gid://gitlab/User/1', name: 'Alice Smith', __typename: 'UserCore' },
        __typename: 'Note',
      },
      __typename: 'AiGovernanceSessionNoteLink',
    },
    {
      id: 'gid://gitlab/Ai::DuoWorkflows::WorkflowNote/2',
      linkType: 'CREATED',
      note: {
        id: 'gid://gitlab/Note/22',
        url: 'http://gdk.test/gitlab-org/security-scanner/-/merge_requests/11#note_22',
        author: { id: 'gid://gitlab/User/2', name: 'Duo Bot', __typename: 'UserCore' },
        __typename: 'Note',
      },
      __typename: 'AiGovernanceSessionNoteLink',
    },
  ]),
  workItemLinks: buildLinkConnection('AiGovernanceSessionWorkItemLinkConnection', [
    {
      id: 'gid://gitlab/Ai::DuoWorkflows::WorkflowWorkItem/1',
      linkType: 'SOURCE',
      workItem: {
        id: 'gid://gitlab/WorkItem/31',
        title: 'Source issue',
        reference: '#31',
        webPath: '/gitlab-org/security-scanner/-/work_items/31',
        workItemType: {
          id: 'gid://gitlab/WorkItems::Type/1',
          name: 'Issue',
          iconName: 'work-item-issue',
          __typename: 'WorkItemType',
        },
        __typename: 'WorkItem',
      },
      __typename: 'AiGovernanceSessionWorkItemLink',
    },
    {
      id: 'gid://gitlab/Ai::DuoWorkflows::WorkflowWorkItem/2',
      linkType: 'CREATED',
      workItem: {
        id: 'gid://gitlab/WorkItem/32',
        title: 'Created task',
        reference: '#32',
        webPath: '/gitlab-org/security-scanner/-/work_items/32',
        workItemType: {
          id: 'gid://gitlab/WorkItems::Type/5',
          name: 'Task',
          iconName: 'work-item-task',
          __typename: 'WorkItemType',
        },
        __typename: 'WorkItem',
      },
      __typename: 'AiGovernanceSessionWorkItemLink',
    },
  ]),
  __typename: 'AiGovernanceSession',
};

export const buildSessionLinksResponse = (parentKey, nodes = [mockSessionLinksNode]) => ({
  data: {
    [parentKey]: {
      id: parentKey === 'project' ? 'gid://gitlab/Project/1' : 'gid://gitlab/Group/1',
      aiGovernanceSessions: {
        nodes,
        __typename: 'AiGovernanceSessionConnection',
      },
      __typename: parentKey === 'project' ? 'Project' : 'Group',
    },
  },
});

export const mockGroupedSessionLinks = {
  startedFrom: [
    {
      id: 'gid://gitlab/MergeRequest/11',
      kind: 'mergeRequest',
      title: 'Source merge request',
      reference: '!11',
      url: '/gitlab-org/security-scanner/-/merge_requests/11',
    },
    {
      id: 'gid://gitlab/WorkItem/31',
      kind: 'workItem',
      title: 'Source issue',
      reference: '#31',
      url: '/gitlab-org/security-scanner/-/work_items/31',
      workItemType: { name: 'Issue', iconName: 'work-item-issue' },
    },
    {
      id: 'gid://gitlab/Note/21',
      kind: 'note',
      title: 'Comment by Alice Smith',
      reference: null,
      url: 'http://gdk.test/gitlab-org/security-scanner/-/merge_requests/11#note_21',
    },
  ],
  created: [
    {
      id: 'gid://gitlab/MergeRequest/12',
      kind: 'mergeRequest',
      title: 'Created merge request',
      reference: '!12',
      url: '/gitlab-org/security-scanner/-/merge_requests/12',
    },
    {
      id: 'gid://gitlab/WorkItem/32',
      kind: 'workItem',
      title: 'Created task',
      reference: '#32',
      url: '/gitlab-org/security-scanner/-/work_items/32',
      workItemType: { name: 'Task', iconName: 'work-item-task' },
    },
    {
      id: 'gid://gitlab/Note/22',
      kind: 'note',
      title: 'Comment by Duo Bot',
      reference: null,
      url: 'http://gdk.test/gitlab-org/security-scanner/-/merge_requests/11#note_22',
    },
  ],
  hasMore: false,
};
