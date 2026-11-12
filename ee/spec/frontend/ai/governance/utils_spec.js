import { useFakeDate } from 'helpers/fake_date';
import { darkModeEnabled } from '~/lib/utils/color_utils';
import {
  agentLogo,
  agentLogoClass,
  auditEventsFilters,
  auditEventsHref,
  formatAgentType,
  formatSessionSource,
  parseSkillguardDetails,
} from 'ee/ai/governance/utils';

jest.mock('~/lib/utils/color_utils');

describe('agentLogo', () => {
  it.each([
    ['codex', 'file-mock-codex.svg'],
    ['cursor', 'file-mock-cursor.svg'],
  ])('returns the logo of the %s agent type', (agentType, logo) => {
    darkModeEnabled.mockReturnValue(false);

    expect(agentLogo(agentType)).toBe(logo);
  });

  it('returns the dark mode logo of the cursor agent type', () => {
    darkModeEnabled.mockReturnValue(true);

    expect(agentLogo('cursor')).toBe('file-mock-cursor-dark.svg');
  });

  it('returns null in dark mode for the codex agent type, which has no dark mark', () => {
    darkModeEnabled.mockReturnValue(true);

    expect(agentLogo('codex')).toBeNull();
  });

  it.each(['claude-code', 'opencode', 'some-new-agent', null])(
    'returns null for the %s agent type',
    (agentType) => {
      expect(agentLogo(agentType)).toBeNull();
    },
  );
});

describe('agentLogoClass', () => {
  it('scales the codex mark up to offset the empty space in its file', () => {
    expect(agentLogoClass('codex')).toBe('gl-scale-150');
  });

  it.each(['cursor', 'claude-code', 'some-new-agent', null])(
    'returns null for the %s agent type',
    (agentType) => {
      expect(agentLogoClass(agentType)).toBeNull();
    },
  );
});

describe('formatAgentType', () => {
  it.each([
    ['claude-code', 'Claude Code'],
    ['cursor', 'Cursor'],
    ['codex', 'Codex'],
  ])('names the %s agent type by its product name', (agentType, name) => {
    expect(formatAgentType(agentType)).toBe(name);
  });
});

describe('formatSessionSource', () => {
  it.each([
    ['cursor', 'Cursor (glab)'],
    ['codex', 'Codex (glab)'],
    ['claude-code', 'Claude Code (glab)'],
  ])('names a glab session with the %s agent type after its agent', (agentType, label) => {
    expect(formatSessionSource({ source: 'CLAUDE_CODE_GLAB', agentType })).toBe(label);
  });

  it('keeps the glab source label when the session has no agent type', () => {
    expect(formatSessionSource({ source: 'CLAUDE_CODE_GLAB', agentType: null })).toBe(
      'Claude Code (glab)',
    );
  });

  it.each([
    ['GITLAB_DUO', 'GitLab Duo'],
    ['CLAUDE_CODE_COMPLIANCE_API', 'Claude Code (Compliance API)'],
    ['MCP', 'GitLab MCP server'],
  ])('labels a %s session by its source alone', (source, label) => {
    expect(formatSessionSource({ source, agentType: 'cursor' })).toBe(label);
  });

  it('returns undefined for an unknown source or a missing session', () => {
    expect(formatSessionSource({ source: 'SOMETHING_NEW', agentType: 'cursor' })).toBeUndefined();
    expect(formatSessionSource(null)).toBeUndefined();
  });
});

describe('auditEventsHref', () => {
  useFakeDate(2026, 9, 19, 10);

  it.each([
    ['LAST_7_DAYS', '2026-10-12'],
    ['LAST_30_DAYS', '2026-09-19'],
  ])('starts the %s link at the start of the window', (timeframe, startTimeAfter) => {
    expect(auditEventsHref(timeframe, { projectPath: 'g/p' })).toBe(
      `?tab=agent-artifacts&projectPath=g%2Fp&startTimeAfter=${startTimeAfter}`,
    );
  });

  it('carries a DAP or Connected agent class', () => {
    expect(auditEventsHref('LAST_7_DAYS', { projectPath: 'g/p', agentClass: 'EXTERNAL' })).toBe(
      '?tab=agent-artifacts&projectPath=g%2Fp&agentClass=EXTERNAL&startTimeAfter=2026-10-12',
    );
  });

  it('leaves out the ALL agent class', () => {
    expect(auditEventsHref('LAST_7_DAYS', { projectPath: 'g/p', agentClass: 'ALL' })).toBe(
      '?tab=agent-artifacts&projectPath=g%2Fp&startTimeAfter=2026-10-12',
    );
  });

  it('leaves the date out for a timeframe it does not know', () => {
    expect(auditEventsHref('LAST_24_HOURS')).toBe('?tab=agent-artifacts');
  });

  it('keeps a start date it is given when no timeframe is set', () => {
    expect(auditEventsHref(null, { projectPath: 'g/p', startTimeAfter: '2026-10-01' })).toBe(
      '?tab=agent-artifacts&projectPath=g%2Fp&startTimeAfter=2026-10-01',
    );
  });
});

describe('auditEventsFilters', () => {
  useFakeDate(2026, 9, 19, 10);

  it('returns the filters with the agent class and the start of the window', () => {
    expect(
      auditEventsFilters('LAST_7_DAYS', { projectPath: 'g/p', agentClass: 'EXTERNAL' }),
    ).toEqual({ projectPath: 'g/p', agentClass: 'EXTERNAL', startTimeAfter: '2026-10-12' });
  });

  it('leaves out the ALL agent class', () => {
    expect(auditEventsFilters('LAST_30_DAYS', { projectPath: 'g/p', agentClass: 'ALL' })).toEqual({
      projectPath: 'g/p',
      startTimeAfter: '2026-09-19',
    });
  });
});

describe('parseSkillguardDetails', () => {
  const text = (fieldName, value) => ({ __typename: 'VulnerabilityDetailText', fieldName, value });
  const list = (values) => ({
    __typename: 'VulnerabilityDetailList',
    items: values.map((value) => ({ __typename: 'VulnerabilityDetailText', value })),
  });
  // The shape the SkillGuard analyzer writes (report/gitlab/convert.go), as GraphQL returns it.
  const details = [
    text('verdict', 'malicious (confidence: 0.98)'),
    {
      __typename: 'VulnerabilityDetailNamedList',
      fieldName: 'checked_facts',
      items: [
        {
          fieldName: 'risk_flags',
          name: 'Risk Flags',
          value: list(['NETWORK_ACCESS', 'ENV_ACCESS']),
        },
        {
          fieldName: 'risk_score',
          name: 'Risk Score',
          value: { __typename: 'VulnerabilityDetailText', value: '95 (DO_NOT_INSTALL)' },
        },
      ],
    },
    {
      __typename: 'VulnerabilityDetailNamedList',
      fieldName: 'kept_findings',
      items: [
        { fieldName: 'finding_001', name: 'Swaps the tool endpoint', value: text(null, '') },
        { fieldName: 'finding_002', name: 'Hides the swap from the user', value: text(null, '') },
      ],
    },
  ];

  it('reads the verdict, confidence, risk score, risk flags and findings', () => {
    expect(parseSkillguardDetails(details)).toEqual({
      verdict: 'malicious',
      confidence: 0.98,
      riskScore: 95,
      riskBand: 'DO_NOT_INSTALL',
      riskFlags: ['NETWORK_ACCESS', 'ENV_ACCESS'],
      findings: ['Swaps the tool endpoint', 'Hides the swap from the user'],
    });
  });

  it('reads a verdict without a confidence and a score without a band', () => {
    const parsed = parseSkillguardDetails([
      text('verdict', 'risky'),
      {
        __typename: 'VulnerabilityDetailNamedList',
        fieldName: 'checked_facts',
        items: [{ fieldName: 'risk_score', name: 'Risk Score', value: text(null, '40') }],
      },
    ]);

    expect(parsed).toMatchObject({
      verdict: 'risky',
      confidence: null,
      riskScore: 40,
      riskBand: null,
    });
  });

  it.each([[undefined], [null], [[]]])('returns empty values for details %p', (input) => {
    expect(parseSkillguardDetails(input)).toEqual({
      verdict: null,
      confidence: null,
      riskScore: null,
      riskBand: null,
      riskFlags: [],
      findings: [],
    });
  });
});
