import { GlAttributeList, GlAvatar, GlButton, GlIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SessionDetailsBody from 'ee/agent_artifacts/components/session_details_body.vue';
import ClientTypeIcon from 'ee/agent_artifacts/components/client_type_icon.vue';
import SessionAuditEventsList from 'ee/agent_artifacts/components/session_audit_events_list.vue';
import SessionLinkedItems from 'ee/agent_artifacts/components/session_linked_items.vue';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import { formatAgentDefinition } from 'ee/ai/duo_agents_platform/utils';
import { DEFAULT_CLIENT_TYPE } from 'ee/agent_artifacts/constants';
import { mockGroupedSessionLinks, mockUser } from '../mock_data';

jest.mock('ee/ai/duo_agents_platform/utils', () => ({
  formatAgentDefinition: jest.fn((name) => name),
}));

describe('SessionDetailsBody', () => {
  let wrapper;

  const mockActiveItem = {
    id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1908',
    sessionId: '1908',
    flowType: 'false_positive_detection/v1',
    sessionStartedAt: '2024-01-01T12:00:00Z',
    webPath: '/gitlab-org/security-scanner/-/automate/agent-sessions/1908',
    downloadPath: '/gitlab-org/security-scanner/-/security/agent_artifacts/1908/download',
    project: {
      name: 'security-scanner',
      webPath: '/gitlab-org/security-scanner',
    },
    triggeredBy: mockUser,
  };

  const createComponent = (props = {}, { slots = {} } = {}) => {
    wrapper = shallowMountExtended(SessionDetailsBody, {
      propsData: {
        activeItem: mockActiveItem,
        sessionId: mockActiveItem.id,
        ...props,
      },
      slots,
      stubs: {
        CrudComponent,
        GlAttributeList,
        GlButton,
        ClientTypeIcon,
        SessionAuditEventsList: true,
      },
    });
  };

  const findTitle = () => wrapper.findByTestId('session-content-title');
  const findAttributeList = () => wrapper.findComponent(GlAttributeList);
  const findRows = () => findAttributeList().props('items');
  const findRow = (type) => findRows().find((item) => item.type === type);
  const findProjectLink = () => wrapper.findByTestId('project-link');
  const findSessionLink = () => wrapper.findByTestId('session-link');
  const findUserContent = () => wrapper.findByTestId('user-content');
  const findUserLink = () => wrapper.findByTestId('user-link');
  const findUserEmpty = () => wrapper.findByTestId('user-empty');
  const findFormattedDate = () => wrapper.findByTestId('formatted-date');
  const findAuditEventsList = () => wrapper.findComponent(SessionAuditEventsList);
  const findLinkedItems = () => wrapper.findComponent(SessionLinkedItems);
  const findDownloadButton = () => wrapper.findComponentByTestId('download-audit-artifact-button');
  const findClientTypeName = () => wrapper.findByTestId('client-type-name');
  const findClientTypeNameIcon = () =>
    wrapper.findByTestId('client-type-name').findComponent(GlIcon);

  beforeEach(() => {
    createComponent();
  });

  it('renders the formatted session title', () => {
    expect(findTitle().text()).toBe(formatAgentDefinition(mockActiveItem.flowType));
    expect(findTitle().element.tagName).toBe('H4');
  });

  it('lists the details side by side with their labels', () => {
    expect(findAttributeList().props('layout')).toBe('horizontal');
  });

  describe('with actions', () => {
    beforeEach(() => {
      createComponent(
        {},
        { slots: { actions: '<button data-testid="extra-action">Revoke</button>' } },
      );
    });

    it('renders them in the title row', () => {
      expect(wrapper.findByTestId('extra-action').exists()).toBe(true);
    });
  });

  describe('in the dashboard side panel', () => {
    beforeEach(() => {
      createComponent({ panelLayout: true });
    });

    it('titles the session by its number', () => {
      expect(findTitle().text()).toBe(`Session #${mockActiveItem.sessionId}`);
      expect(findTitle().element.tagName).toBe('H2');
    });

    it('stacks each label above its value', () => {
      expect(findAttributeList().props('layout')).toBe('vertical');
    });
  });

  it('names an external session without a flow type by its source', () => {
    createComponent({
      activeItem: { ...mockActiveItem, flowType: null, source: 'CLAUDE_CODE_GLAB' },
    });

    expect(findTitle().text()).toBe('Claude Code (glab)');
  });

  it('renders every row inline with an icon on the label', () => {
    expect(findAttributeList().props('layout')).toBe('horizontal');
    expect(findRows().map((item) => [item.label, item.icon])).toEqual([
      ['Session', 'session-ai'],
      ['User', 'user'],
      ['Date', 'clock'],
      ['Project', 'project'],
      ['Client type', 'agent-ai'],
    ]);
  });

  describe('when the session belongs to a project', () => {
    it('renders the session row linking to the session', () => {
      expect(findRow('session')).toBeDefined();
      expect(findSessionLink().attributes('href')).toBe(mockActiveItem.webPath);
      expect(findSessionLink().text()).toBe('#1908');
    });

    it('renders the project row', () => {
      expect(findRow('project')).toBeDefined();
    });

    it('renders the project link from the active item', () => {
      expect(findProjectLink().exists()).toBe(true);
      expect(findProjectLink().attributes('href')).toBe(mockActiveItem.project.webPath);
    });

    it('renders the date row', () => {
      expect(findRow('date')).toBeDefined();
      expect(findFormattedDate().exists()).toBe(true);
    });
  });

  describe('when the session has no web path (external session)', () => {
    const externalItem = {
      ...mockActiveItem,
      id: 'gid://gitlab/Ai::Governance::Session/502',
      sessionId: '3f2b1c9e-6a7d',
      source: 'CLAUDE_CODE_GLAB',
      webPath: null,
      downloadPath: null,
    };

    beforeEach(() => {
      createComponent({ activeItem: externalItem, sessionId: externalItem.id });
    });

    it('does not render the view full session details button', () => {
      expect(wrapper.findByTestId('view-full-session-details-button').exists()).toBe(false);
    });

    it('renders the source session id as text instead of a link', () => {
      expect(findSessionLink().exists()).toBe(false);
      expect(wrapper.findByTestId('session-text').text()).toBe('#3f2b1c9e-6a7d');
    });
  });

  describe('when the session belongs to a group (no project)', () => {
    beforeEach(() => {
      createComponent({ activeItem: { ...mockActiveItem, project: null } });
    });

    it('does not render the session row', () => {
      expect(findRow('session')).toBeUndefined();
    });

    it('renders the project row with a hyphen placeholder', () => {
      expect(findRow('project')).toBeDefined();
      expect(findProjectLink().exists()).toBe(false);
      expect(wrapper.findByTestId('project-empty').text()).toBe('—');
    });

    it('still renders the date row', () => {
      expect(findRow('date')).toBeDefined();
    });

    it('still renders the client type row', () => {
      expect(findRow('clientType')).toBeDefined();
    });
  });

  describe('client type row', () => {
    it('renders the client type row', () => {
      expect(findRow('clientType')).toBeDefined();
    });

    it('renders the default client type icon next to the client type name', () => {
      expect(findClientTypeNameIcon().exists()).toBe(true);
      expect(findClientTypeNameIcon().props('name')).toBe(DEFAULT_CLIENT_TYPE.icon);
    });

    it('renders the default client type name', () => {
      expect(findClientTypeName().text()).toContain(DEFAULT_CLIENT_TYPE.name);
    });

    describe('when the session was run by an external agent', () => {
      beforeEach(() => {
        createComponent({ activeItem: { ...mockActiveItem, agentType: 'claude-code' } });
      });

      it('renders an initial avatar instead of a sprite icon', () => {
        const avatar = findClientTypeName().findComponent(GlAvatar);

        expect(avatar.exists()).toBe(true);
        expect(avatar.props('entityName')).toBe('Claude Code');
        expect(findClientTypeNameIcon().exists()).toBe(false);
      });

      it('renders the agent type name', () => {
        expect(findRow('clientType').text).toBe('Claude Code');
      });
    });

    describe.each([
      ['cursor', 'file-mock-cursor.svg'],
      ['codex', 'file-mock-codex.svg'],
    ])('when the session was run by %s', (agentType, logo) => {
      beforeEach(() => {
        createComponent({ activeItem: { ...mockActiveItem, agentType } });
      });

      it('renders the agent logo instead of an avatar', () => {
        const img = findClientTypeName().findComponent(ClientTypeIcon).find('img');

        expect(img.element.src).toBe(logo);
        expect(img.classes('gl-scale-150')).toBe(agentType === 'codex');
        expect(findClientTypeName().findComponent(GlAvatar).exists()).toBe(false);
      });
    });

    describe('when the session comes from the GitLab MCP server', () => {
      beforeEach(() => {
        createComponent({
          activeItem: { ...mockActiveItem, flowType: null, source: 'MCP', agentType: 'unknown' },
        });
      });

      it('renders the GitLab MCP server name', () => {
        expect(findRow('clientType').text).toBe('GitLab MCP server');
        expect(findTitle().text()).toBe('GitLab MCP server');
      });

      it('renders the GitLab logo', () => {
        expect(findClientTypeNameIcon().props('name')).toBe('tanuki');
      });
    });

    describe('when the agent type is not a known value', () => {
      beforeEach(() => {
        createComponent({ activeItem: { ...mockActiveItem, agentType: 'some-new-agent' } });
      });

      it('renders the humanised agent type', () => {
        expect(findRow('clientType').text).toBe('Some new agent');
      });
    });
  });

  describe('user row', () => {
    it('renders the user row', () => {
      expect(findRow('user')).toBeDefined();
    });

    it('renders the user name link when triggeredBy is present', () => {
      expect(findUserContent().exists()).toBe(true);
      expect(findUserLink().attributes('href')).toBe(mockUser.webPath);
      expect(findUserLink().text()).toBe(mockUser.name);
    });

    it('renders a hyphen when triggeredBy is null', () => {
      createComponent({ activeItem: { ...mockActiveItem, triggeredBy: null } });

      expect(findUserContent().exists()).toBe(false);
      expect(findUserEmpty().text()).toBe('—');
    });
  });

  describe('download audit artifact button', () => {
    it('renders the button with a download icon', () => {
      expect(findDownloadButton().exists()).toBe(true);
      expect(findDownloadButton().props('icon')).toBe('download');
    });

    it('renders the button label', () => {
      expect(findDownloadButton().text()).toBe('Download Session Artifacts');
    });

    it('links to the download path of the active item', () => {
      expect(findDownloadButton().attributes('href')).toBe(mockActiveItem.downloadPath);
    });

    it('does not render the button when there is no download path', () => {
      createComponent({
        activeItem: { ...mockActiveItem, downloadPath: null },
      });

      expect(findDownloadButton().exists()).toBe(false);
    });
  });

  describe('audit events list', () => {
    it('renders the list when session id is present', () => {
      expect(findAuditEventsList().exists()).toBe(true);
    });

    it('does not render the list when there is no session id', () => {
      createComponent({ sessionId: null });

      expect(findAuditEventsList().exists()).toBe(false);
    });

    it('passes events, pageInfo, isLoading and hasError through to the list', () => {
      const events = [{ id: 'event-1' }];
      const pageInfo = { hasNextPage: true };

      createComponent({ events, pageInfo, isLoading: true, hasError: true });

      expect(findAuditEventsList().props('events')).toBe(events);
      expect(findAuditEventsList().props('pageInfo')).toBe(pageInfo);
      expect(findAuditEventsList().props('isLoading')).toBe(true);
      expect(findAuditEventsList().props('hasError')).toBe(true);
    });

    it('re-emits select when the list emits select', () => {
      const event = { id: 'event-1' };

      findAuditEventsList().vm.$emit('select', event);

      expect(wrapper.emitted('select')).toEqual([[event]]);
    });

    it('re-emits next when the list emits next', () => {
      findAuditEventsList().vm.$emit('next', 'cursor-1');

      expect(wrapper.emitted('next')).toEqual([['cursor-1']]);
    });

    it('re-emits prev when the list emits prev', () => {
      findAuditEventsList().vm.$emit('prev', 'cursor-1');

      expect(wrapper.emitted('prev')).toEqual([['cursor-1']]);
    });
  });

  describe('linked items', () => {
    it('renders the linked items with both groups when there are links', () => {
      createComponent({ links: mockGroupedSessionLinks });

      expect(findLinkedItems().props()).toEqual({
        startedFrom: mockGroupedSessionLinks.startedFrom,
        created: mockGroupedSessionLinks.created,
        hasMore: false,
        sessionPath: mockActiveItem.webPath,
      });
    });

    it('passes on that more links exist', () => {
      createComponent({ links: { ...mockGroupedSessionLinks, hasMore: true } });

      expect(findLinkedItems().props('hasMore')).toBe(true);
    });

    it('renders the linked items when only more links exist', () => {
      createComponent({ links: { startedFrom: [], created: [], hasMore: true } });

      expect(findLinkedItems().exists()).toBe(true);
    });

    it('passes no session path when the active item has none', () => {
      createComponent({
        activeItem: { ...mockActiveItem, webPath: null },
        links: mockGroupedSessionLinks,
      });

      expect(findLinkedItems().props('sessionPath')).toBeNull();
    });

    it('renders the linked items when only one group has links', () => {
      createComponent({ links: { startedFrom: [], created: mockGroupedSessionLinks.created } });

      expect(findLinkedItems().exists()).toBe(true);
    });

    it.each([
      ['null', null],
      ['empty', { startedFrom: [], created: [] }],
    ])('does not render the linked items when links are %s', (_, links) => {
      createComponent({ links });

      expect(findLinkedItems().exists()).toBe(false);
    });

    it('renders the linked items between the session details and the audit events', () => {
      createComponent({ links: mockGroupedSessionLinks });

      const children = [...wrapper.element.children];
      const crudIndex = children.indexOf(wrapper.findComponent(CrudComponent).element);
      const linksIndex = children.indexOf(findLinkedItems().element);
      const eventsIndex = children.indexOf(findAuditEventsList().element);

      expect(crudIndex).toBeLessThan(linksIndex);
      expect(linksIndex).toBeLessThan(eventsIndex);
    });
  });
});
