import {
  focusPanel,
  formatEventName,
  formatSessionName,
  getClientType,
  groupSessionLinks,
  normalizeLegacySession,
} from 'ee/agent_artifacts/utils';
import {
  buildLinkConnection,
  mockArtifactNodes,
  mockGroupedSessionLinks,
  mockSessionLinksNode,
} from './mock_data';

describe('focusPanel', () => {
  let panel;

  beforeEach(() => {
    panel = document.createElement('div');
    document.body.appendChild(panel);
  });

  afterEach(() => {
    panel.remove();
  });

  it('focuses the panel, focusable only until focus leaves it', () => {
    focusPanel(panel);
    expect(document.activeElement).toBe(panel);
    expect(panel.getAttribute('tabindex')).toBe('-1');

    panel.blur();
    expect(panel.hasAttribute('tabindex')).toBe(false);
  });

  it('keeps a tabindex the panel already has', () => {
    panel.setAttribute('tabindex', '0');
    focusPanel(panel);
    panel.blur();

    expect(panel.getAttribute('tabindex')).toBe('0');
  });

  it('does nothing without a panel', () => {
    expect(() => focusPanel(undefined)).not.toThrow();
  });
});

describe('normalizeLegacySession', () => {
  it('maps a session artifact onto the governance session shape', () => {
    const [node] = mockArtifactNodes;

    expect(normalizeLegacySession(node)).toEqual({
      ...node,
      flowType: 'false_positive_detection/v1',
      sessionStartedAt: '2026-03-05T22:14:17Z',
      sessionId: '1908',
    });
  });
});

describe('formatSessionName', () => {
  it('formats the flow type when present', () => {
    expect(formatSessionName({ flowType: 'code_review/v1', source: 'GITLAB_DUO' })).toBe(
      'Code review/v1',
    );
  });

  it.each([
    ['CLAUDE_CODE_GLAB', 'Claude Code (glab)'],
    ['CLAUDE_CODE_COMPLIANCE_API', 'Claude Code (Compliance API)'],
  ])('falls back to the %s source label when there is no flow type', (source, label) => {
    expect(formatSessionName({ flowType: null, source })).toBe(label);
  });

  it.each([
    ['cursor', 'Cursor (glab)'],
    ['codex', 'Codex (glab)'],
    ['claude-code', 'Claude Code (glab)'],
    [null, 'Claude Code (glab)'],
  ])('names a glab session with the %s agent type after its agent', (agentType, label) => {
    expect(formatSessionName({ flowType: null, source: 'CLAUDE_CODE_GLAB', agentType })).toBe(
      label,
    );
  });

  it('falls back to the MCP source label when there is no flow type', () => {
    expect(formatSessionName({ flowType: null, source: 'MCP' })).toBe('GitLab MCP server');
  });

  it('falls back to the generic agent session name without a flow type or known source', () => {
    expect(formatSessionName({ flowType: null })).toBe('Agent session');
  });
});

describe('getClientType', () => {
  it.each([null, undefined])('returns the GitLab Duo default when agentType is %s', (agentType) => {
    expect(getClientType({ agentType })).toEqual({
      name: 'GitLab Duo',
      icon: 'tanuki-ai',
    });
  });

  it.each([
    ['claude-code', 'Claude Code'],
    ['opencode', 'OpenCode'],
    ['cursor', 'Cursor'],
    ['codex', 'Codex'],
  ])('returns the named entry for known agent type %s', (agentType, name) => {
    expect(getClientType({ agentType })).toEqual({ name });
  });

  it('humanises unknown agent types instead of falling back to GitLab Duo', () => {
    expect(getClientType({ agentType: 'some-new-agent' })).toEqual({ name: 'Some new agent' });
  });

  describe('when the session source is MCP', () => {
    it.each(['unknown', null, undefined])(
      'returns the GitLab MCP server with the GitLab logo when agentType is %s',
      (agentType) => {
        expect(getClientType({ source: 'MCP', agentType })).toEqual({
          name: 'GitLab MCP server',
          icon: 'tanuki',
        });
      },
    );

    it('keeps the name of a recognised agent type', () => {
      expect(getClientType({ source: 'MCP', agentType: 'cursor' })).toEqual({ name: 'Cursor' });
    });
  });

  it('humanises the unknown agent type when the source is not MCP', () => {
    expect(getClientType({ source: 'CLAUDE_CODE_GLAB', agentType: 'unknown' })).toEqual({
      name: 'Unknown',
    });
  });
});

describe('formatEventName', () => {
  describe('with ai_ prefix', () => {
    it.each([
      ['ai_agent_session_ended', 'Agent session ended'],
      ['ai_llm_input_sent', 'Llm input sent'],
      ['ai_tool_invoked', 'Tool invoked'],
    ])('converts %s to %s', (input, expected) => {
      expect(formatEventName(input)).toBe(expected);
    });
  });

  describe('without ai_ prefix', () => {
    it('capitalises the first letter and replaces underscores with spaces', () => {
      expect(formatEventName('tool_execution')).toBe('Tool execution');
    });
  });

  describe('falsy input guard', () => {
    it.each([null, undefined, ''])('returns an empty string for %s', (input) => {
      expect(formatEventName(input)).toBe('');
    });
  });
});

describe('groupSessionLinks', () => {
  it('groups links into the items the session started from and created', () => {
    expect(groupSessionLinks(mockSessionLinksNode)).toEqual(mockGroupedSessionLinks);
  });

  it('leaves out links whose item the user cannot read', () => {
    const { created } = groupSessionLinks(mockSessionLinksNode);

    expect(created.map(({ id }) => id)).toEqual([
      'gid://gitlab/MergeRequest/12',
      'gid://gitlab/WorkItem/32',
      'gid://gitlab/Note/22',
    ]);
  });

  it('names a comment after its author without escaping the name', () => {
    const session = {
      noteLinks: {
        nodes: [
          {
            linkType: 'TRIGGERED',
            note: { id: 'gid://gitlab/Note/1', url: '/note', author: { name: "O'Brien" } },
          },
        ],
      },
    };

    expect(groupSessionLinks(session).startedFrom[0].title).toBe("Comment by O'Brien");
  });

  it('names a comment without an author with a generic title', () => {
    const session = {
      noteLinks: {
        nodes: [
          {
            linkType: 'TRIGGERED',
            note: { id: 'gid://gitlab/Note/1', url: '/note', author: null },
          },
        ],
      },
    };

    expect(groupSessionLinks(session).startedFrom[0].title).toBe('Comment');
  });

  it.each([
    ['empty connections', { mergeRequestLinks: { nodes: [] }, noteLinks: { nodes: [] } }],
    ['missing connections', { id: 'gid://gitlab/Ai::Governance::Session/1' }],
    ['null connections', { mergeRequestLinks: null, noteLinks: null, workItemLinks: null }],
    ['no session', null],
  ])('returns empty groups for %s', (_, session) => {
    expect(groupSessionLinks(session)).toEqual({ startedFrom: [], created: [], hasMore: false });
  });

  it.each(['mergeRequestLinks', 'noteLinks', 'workItemLinks'])(
    'reports more links when %s has a next page',
    (key) => {
      const session = { ...mockSessionLinksNode, [key]: buildLinkConnection(key, [], true) };

      expect(groupSessionLinks(session).hasMore).toBe(true);
    },
  );

  it('does not report more links when no connection has a next page', () => {
    expect(groupSessionLinks(mockSessionLinksNode).hasMore).toBe(false);
  });

  it('does not report more links when a connection has no page info', () => {
    const session = { mergeRequestLinks: { nodes: [], pageInfo: null }, noteLinks: { nodes: [] } };

    expect(groupSessionLinks(session).hasMore).toBe(false);
  });
});
