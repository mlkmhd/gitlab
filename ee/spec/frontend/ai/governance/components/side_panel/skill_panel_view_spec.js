import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlLoadingIcon } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import SkillPanelView from 'ee/ai/governance/components/side_panel/skill_panel_view.vue';
import getSkillguardSkillQuery from 'ee/ai/governance/graphql/queries/get_skillguard_skill.query.graphql';

Vue.use(VueApollo);

const VULNERABILITY_ID = 'gid://gitlab/Vulnerability/7';

const text = (value, fieldName = null) => ({
  __typename: 'VulnerabilityDetailText',
  fieldName,
  value,
});
const list = (values) => ({
  __typename: 'VulnerabilityDetailList',
  items: values.map((value) => ({ __typename: 'VulnerabilityDetailText', value })),
});
const namedList = (fieldName, items) => ({
  __typename: 'VulnerabilityDetailNamedList',
  fieldName,
  items: items.map((item) => ({ __typename: 'VulnerabilityDetailNamedListItem', ...item })),
});

// Shaped like a finding the SkillGuard analyzer publishes (report/gitlab/convert.go).
const ANALYZER_DETAILS = [
  text('malicious (confidence: 0.98)', 'verdict'),
  namedList('checked_facts', [
    { fieldName: 'risk_flags', name: 'Risk Flags', value: list(['NETWORK_ACCESS', 'ENV_ACCESS']) },
    { fieldName: 'risk_score', name: 'Risk Score', value: text('95 (DO_NOT_INSTALL)') },
  ]),
  namedList('kept_findings', [
    { fieldName: 'finding_001', name: 'Swaps the tool endpoint', value: text('Category: AG02.') },
    { fieldName: 'finding_002', name: 'Hides the swap', value: text('Category: AG01.') },
  ]),
];

const vulnerability = (overrides = {}) => ({
  __typename: 'Vulnerability',
  id: VULNERABILITY_ID,
  title: '0x-swap',
  severity: 'CRITICAL',
  state: 'DETECTED',
  detectedAt: '2026-11-09T07:16:19Z',
  description:
    'The skill swaps the configured tool endpoint for another host after the first call.',
  vulnerabilityPath: '/gitlab-duo/data-pipeline/-/security/vulnerabilities/7',
  location: {
    __typename: 'VulnerabilityLocationSast',
    file: '.claude/skills/0x-swap/SKILL.md',
    blobPath: '/gitlab-duo/data-pipeline/-/blob/abc123/.claude/skills/0x-swap/SKILL.md',
  },
  identifiers: [
    {
      __typename: 'VulnerabilityIdentifier',
      externalType: 'skillguard',
      externalId: 'skillguard-skill-analysis',
      name: 'SkillGuard Skill Analysis',
    },
    {
      __typename: 'VulnerabilityIdentifier',
      externalType: 'owasp_agentic',
      externalId: 'AG02',
      name: 'AG02 - Insecure Tool Utilization',
    },
  ],
  project: {
    __typename: 'Project',
    id: 'gid://gitlab/Project/2',
    name: 'data-pipeline',
    webPath: '/gitlab-duo/data-pipeline',
  },
  details: ANALYZER_DETAILS,
  ...overrides,
});

describe('SkillPanelView', () => {
  let wrapper;
  let handler;

  const createComponent = ({
    response = { data: { vulnerability: vulnerability() } },
    queryHandler = jest.fn().mockResolvedValue(response),
  } = {}) => {
    handler = queryHandler;
    wrapper = mountExtended(SkillPanelView, {
      apolloProvider: createMockApollo([[getSkillguardSkillQuery, handler]]),
      propsData: { vulnerabilityId: VULNERABILITY_ID },
    });
  };

  const findText = (testId) => wrapper.findByTestId(testId).text();
  const listItems = (testId) =>
    wrapper
      .findByTestId(testId)
      .findAll('li')
      .wrappers.map((item) => item.text());

  it('loads the skill by its vulnerability', () => {
    createComponent();

    expect(handler).toHaveBeenCalledWith({ id: VULNERABILITY_ID });
    expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(true);
  });

  describe('with a finding from the SkillGuard analyzer', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it("shows the analyzer's verdict and why it flagged the skill", () => {
      expect(findText('skill-verdict')).toBe('Malicious');
      expect(findText('skill-description')).toBe(
        'The skill swaps the configured tool endpoint for another host after the first call.',
      );
    });

    it('links to the vulnerability in the Vulnerability report', () => {
      const link = wrapper.findByTestId('skill-vulnerability-link');

      expect(link.text()).toBe('View in vulnerability report');
      expect(link.attributes('href')).toBe(
        '/gitlab-duo/data-pipeline/-/security/vulnerabilities/7',
      );
    });

    it('shows the status, detection time, confidence and risk score', () => {
      expect(findText('skill-status')).toBe('Needs triage');
      expect(wrapper.findComponent(TimeAgoTooltip).props('time')).toBe('2026-11-09T07:16:19Z');
      expect(findText('skill-confidence')).toBe('98%');
      expect(findText('skill-risk-score')).toBe('95 (Do not install)');
    });

    it('links to the skill file and the project it was found in', () => {
      expect(wrapper.findByTestId('skill-file').text()).toBe('.claude/skills/0x-swap/SKILL.md');
      expect(wrapper.findByTestId('skill-file').attributes('href')).toBe(
        '/gitlab-duo/data-pipeline/-/blob/abc123/.claude/skills/0x-swap/SKILL.md',
      );
      expect(wrapper.findByTestId('skill-project').text()).toBe('data-pipeline');
      expect(wrapper.findByTestId('skill-project').attributes('href')).toBe(
        '/gitlab-duo/data-pipeline',
      );
    });

    it('lists what SkillGuard found, its risk flags and its OWASP agentic categories', () => {
      expect(listItems('skill-findings')).toEqual(['Swaps the tool endpoint', 'Hides the swap']);
      expect(listItems('skill-risk-flags')).toEqual(['NETWORK_ACCESS', 'ENV_ACCESS']);
      expect(listItems('skill-categories')).toEqual(['AG02 - Insecure Tool Utilization']);
    });
  });

  it("shows the analyzer's verdict when it differs from the severity", async () => {
    createComponent({ response: { data: { vulnerability: vulnerability({ severity: 'HIGH' }) } } });
    await waitForPromises();

    expect(findText('skill-verdict')).toBe('Malicious');
  });

  it('falls back to the verdict for its severity when the analyzer verdict is unknown', async () => {
    createComponent({
      response: {
        data: {
          vulnerability: vulnerability({ details: [text('benign (confidence: 0.40)', 'verdict')] }),
        },
      },
    });
    await waitForPromises();

    expect(findText('skill-verdict')).toBe('Malicious');
    expect(findText('skill-confidence')).toBe('40%');
  });

  it('shows a risk score without a band as the score alone', async () => {
    createComponent({
      response: {
        data: {
          vulnerability: vulnerability({
            details: [
              namedList('checked_facts', [
                { fieldName: 'risk_score', name: 'Risk Score', value: text('40') },
              ]),
            ],
          }),
        },
      },
    });
    await waitForPromises();

    expect(findText('skill-risk-score')).toBe('40');
  });

  it('leaves out the file and project when the finding has none', async () => {
    createComponent({
      response: { data: { vulnerability: vulnerability({ location: null, project: null }) } },
    });
    await waitForPromises();

    expect(wrapper.findByTestId('skill-panel').exists()).toBe(true);
    expect(wrapper.findByTestId('skill-file').exists()).toBe(false);
    expect(wrapper.findByTestId('skill-project').exists()).toBe(false);
  });

  describe('with a finding that has no analyzer details', () => {
    beforeEach(async () => {
      createComponent({
        response: { data: { vulnerability: vulnerability({ severity: 'HIGH', details: [] }) } },
      });
      await waitForPromises();
    });

    it('falls back to the verdict for its severity', () => {
      expect(findText('skill-verdict')).toBe('Suspicious');
    });

    it('leaves out what the analyzer did not say', () => {
      expect(wrapper.findByTestId('skill-confidence').exists()).toBe(false);
      expect(wrapper.findByTestId('skill-risk-score').exists()).toBe(false);
      expect(wrapper.findByTestId('skill-findings').exists()).toBe(false);
      expect(wrapper.findByTestId('skill-risk-flags').exists()).toBe(false);
    });
  });

  it('says so when the skill cannot be found', async () => {
    createComponent({ response: { data: { vulnerability: null } } });
    await waitForPromises();

    expect(wrapper.findByTestId('skill-not-found').text()).toBe(
      'This skill could not be found, or you do not have permission to view it.',
    );
  });

  it('shows an error when the skill fails to load', async () => {
    createComponent({ queryHandler: jest.fn().mockRejectedValue(new Error('boom')) });
    await waitForPromises();

    expect(wrapper.findComponent(GlAlert).text()).toBe('Failed to load this skill.');
  });
});
