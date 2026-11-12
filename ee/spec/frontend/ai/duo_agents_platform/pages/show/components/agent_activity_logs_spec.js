import { nextTick } from 'vue';
import { GlSkeletonLoader } from '@gitlab/ui';
import { DuoChatContextConversation as DuoChatConversation } from '@gitlab/duo-ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AgentActivityLogs from 'ee/ai/duo_agents_platform/pages/show/components/agent_activity_logs.vue';
import AgentFlowEmptyState from 'ee/ai/duo_agents_platform/components/common/agent_flow_empty_state.vue';
import MessageTodoChecklist from 'ee/ai/duo_agents_platform/components/common/message_todo_checklist.vue';
import { mockItems } from '../../../components/common/mock';

describe('AgentActivityLogs', () => {
  let wrapper;

  const findChatConversation = () => wrapper.findComponent(DuoChatConversation);
  const findSkeletonLoader = () => wrapper.findAllComponents(GlSkeletonLoader);
  const findEmptyState = () => wrapper.findComponent(AgentFlowEmptyState);
  const findLoadOlderMessagesButton = () =>
    wrapper.findComponentByTestId('load-older-messages-button');

  const defaultProps = {
    isLoading: false,
    duoMessages: [],
    createdAt: '2022-03-11T04:30:00Z',
    updatedAt: '2022-03-11T04:35:00Z',
    status: 'FINISHED',
    user: {},
  };

  const createWrapper = (props = {}) => {
    wrapper = shallowMountExtended(AgentActivityLogs, {
      propsData: { ...defaultProps, ...props },
    });
  };

  const createAttachedWrapper = (props = {}) => {
    wrapper = mountExtended(AgentActivityLogs, {
      propsData: { ...defaultProps, ...props },
      stubs: { DuoChatConversation: true },
      attachTo: document.body,
    });
  };

  describe('when loading', () => {
    beforeEach(() => createWrapper({ isLoading: true }));

    it('renders skeleton loaders', () => {
      expect(findSkeletonLoader().exists()).toBe(true);
    });

    it('does not render the empty state or chat conversation', () => {
      expect(findEmptyState().exists()).toBe(false);
      expect(findChatConversation().exists()).toBe(false);
    });
  });

  describe('with no messages', () => {
    beforeEach(() => createWrapper({ duoMessages: [] }));

    it('renders the empty state', () => {
      expect(findEmptyState().exists()).toBe(true);
    });

    it('does not render the chat conversation or skeleton loaders', () => {
      expect(findChatConversation().exists()).toBe(false);
      expect(findSkeletonLoader().exists()).toBe(false);
    });
  });

  describe('with messages', () => {
    beforeEach(() => {
      createWrapper({ duoMessages: mockItems });
    });

    it('renders DuoChatConversation', () => {
      expect(findChatConversation().exists()).toBe(true);
    });

    it('passes transformed messages to DuoChatConversation', () => {
      const messages = findChatConversation().props('messages');

      expect(messages).toHaveLength(mockItems.length);
      expect(messages[1]).toMatchObject({
        message_type: mockItems[1].messageType,
        role: expect.any(String),
      });
    });

    it('disables feedback, code insertion, and delimiter', () => {
      expect(findChatConversation().props('showDelimiter')).toBe(false);
      expect(findChatConversation().props('withFeedback')).toBe(false);
      expect(findChatConversation().props('enableCodeInsertion')).toBe(false);
    });

    it('passes messageRenderers with the approval request renderer', () => {
      const renderers = findChatConversation().props('messageRenderers');

      expect(renderers).toHaveLength(2);
      expect(renderers[0].matchMessage({ message_type: 'request' })).toBe(true);
      expect(renderers[0].matchMessage({ message_type: 'agent' })).toBe(false);
    });

    it('passes messageRenderers with the todo_write renderer', () => {
      const renderers = findChatConversation().props('messageRenderers');
      const todoRenderer = renderers.find((r) => r.component === MessageTodoChecklist);

      expect(todoRenderer.matchMessage({ tool_info: { name: 'todo_write' } })).toBe(true);
      expect(todoRenderer.matchMessage({ tool_info: JSON.stringify({ name: 'todo_write' }) })).toBe(
        true,
      );
      expect(todoRenderer.matchMessage({ tool_info: { name: 'read_file' } })).toBe(false);
      expect(todoRenderer.matchMessage({ tool_info: null })).toBe(false);
      expect(todoRenderer.matchMessage({})).toBe(false);
    });
  });

  describe('with an external flow pause message', () => {
    beforeEach(() => {
      createWrapper({
        duoMessages: [...mockItems, { messageType: 'request', messageSubType: 'external' }],
      });
    });

    it('stamps the matching message with message_sub_type and isLastMessage', () => {
      const messages = findChatConversation().props('messages');
      const externalMessage = messages[messages.length - 1];

      expect(externalMessage).toMatchObject({
        message_sub_type: 'external',
        isLastMessage: true,
      });
    });
  });

  describe('load more button', () => {
    describe('when there are no older messages', () => {
      beforeEach(() => createWrapper({ duoMessages: mockItems }));

      it('does not render the button', () => {
        expect(findLoadOlderMessagesButton().exists()).toBe(false);
      });

      it('renders the session start', () => {
        expect(findEmptyState().exists()).toBe(true);
      });
    });

    describe('when there are older messages', () => {
      beforeEach(() => createWrapper({ duoMessages: mockItems, hasOlderMessages: true }));

      it('renders the button', () => {
        expect(findLoadOlderMessagesButton().text()).toBe('Load earlier messages');
        expect(findLoadOlderMessagesButton().props('loading')).toBe(false);
      });

      it('does not render the session start', () => {
        expect(findEmptyState().exists()).toBe(false);
      });

      describe('when the button is clicked', () => {
        beforeEach(() => {
          findLoadOlderMessagesButton().vm.$emit('click');
        });

        it('emits load-older-messages', () => {
          expect(wrapper.emitted('load-older-messages')).toHaveLength(1);
        });
      });
    });

    describe('while older messages are loading', () => {
      beforeEach(() =>
        createWrapper({
          duoMessages: mockItems,
          hasOlderMessages: true,
          isLoadingOlderMessages: true,
        }),
      );

      it('shows the button as loading', () => {
        expect(findLoadOlderMessagesButton().props('loading')).toBe(true);
      });
    });

    describe('when the oldest messages load while the button has focus', () => {
      beforeEach(async () => {
        createAttachedWrapper({ duoMessages: mockItems, hasOlderMessages: true });
        findLoadOlderMessagesButton().element.focus();

        await wrapper.setProps({ hasOlderMessages: false });
        await nextTick();
      });

      it('moves focus to the start of the activity log', () => {
        expect(document.activeElement).toBe(wrapper.findByTestId('activity-log').element);
      });
    });

    describe('when the oldest messages load while focus is elsewhere', () => {
      beforeEach(async () => {
        createAttachedWrapper({ duoMessages: mockItems, hasOlderMessages: true });

        await wrapper.setProps({ hasOlderMessages: false });
        await nextTick();
      });

      it('keeps focus where it was', () => {
        expect(document.activeElement).toBe(document.body);
      });
    });
  });

  describe('goal message', () => {
    const goal = 'Fix the failing pipeline';
    const findMessages = () => findChatConversation().props('messages');

    it.each`
      description                 | content
      ${'v1 flow prefix'}         | ${`Starting Flow: ${goal}`}
      ${'legacy workflow prefix'} | ${`Starting workflow with goal: ${goal}`}
      ${'no known prefix'}        | ${goal}
    `(
      'renders a first tool entry without tool_info with $description as a user message',
      ({ content }) => {
        createWrapper({
          duoMessages: [{ messageType: 'tool', toolInfo: null, content }, ...mockItems],
        });

        expect(findMessages()[0]).toMatchObject({
          role: 'user',
          message_type: 'user',
          content: goal,
        });
      },
    );

    it('leaves a chat session whose first entry is already a user message unchanged', () => {
      createWrapper({ duoMessages: [{ messageType: 'user', content: goal }, ...mockItems] });

      expect(findMessages()[0]).toMatchObject({
        role: 'user',
        message_type: 'user',
        content: goal,
      });
    });

    describe('when older messages are not loaded yet', () => {
      beforeEach(() => {
        createWrapper({
          duoMessages: [{ messageType: 'tool', toolInfo: null, content: goal }, ...mockItems],
          hasOlderMessages: true,
        });
      });

      it('leaves the first loaded tool entry unchanged', () => {
        expect(findMessages()[0]).toMatchObject({
          role: 'tool',
          message_type: 'tool',
          content: goal,
        });
      });
    });

    it('leaves a later tool entry without tool_info unchanged', () => {
      const content = `Starting Flow: ${goal}`;
      createWrapper({
        duoMessages: [
          { messageType: 'agent', content: 'Hello' },
          { messageType: 'tool', toolInfo: null, content },
        ],
      });

      expect(findMessages()[1]).toMatchObject({
        role: 'tool',
        message_type: 'tool',
        content,
      });
    });
  });

  describe('todo_write spinner freezing', () => {
    const todoMessage = (todos) => ({
      messageType: 'tool',
      toolInfo: JSON.stringify({ name: 'todo_write', args: { todos } }),
    });
    const todoMessages = [
      todoMessage([{ description: 'first plan', status: 'in_progress' }]),
      todoMessage([{ description: 'second plan', status: 'in_progress' }]),
    ];
    const findTodoMessages = () =>
      findChatConversation()
        .props('messages')
        .filter((message) => message.tool_info?.name === 'todo_write');

    describe('when the session is still running', () => {
      beforeEach(() => {
        createWrapper({ duoMessages: todoMessages, status: 'RUNNING' });
      });

      it('marks earlier todo lists as finished and leaves the latest one active', () => {
        const todos = findTodoMessages();
        expect(todos[0].todoFinished).toBe(true);
        expect(todos[1].todoFinished).toBe(false);
      });
    });

    describe('when the session has reached a terminal state', () => {
      beforeEach(() => {
        createWrapper({ duoMessages: todoMessages, status: 'FINISHED' });
      });

      it('freezes all todo lists', () => {
        expect(findTodoMessages().every((message) => message.todoFinished)).toBe(true);
      });
    });
  });

  describe('when session has failed', () => {
    beforeEach(() => {
      createWrapper({ duoMessages: mockItems, status: 'FAILED' });
    });

    it('does not append a session failed error bubble to chatMessages', () => {
      const messages = findChatConversation().props('messages');
      const lastMessage = messages[messages.length - 1];

      expect(lastMessage.requestId).not.toBe('session-failed');
    });
  });
});
