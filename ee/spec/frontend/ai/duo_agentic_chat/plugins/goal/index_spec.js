import { goalPlugin } from 'ee/ai/duo_agentic_chat/plugins/goal';
import MessageGoalPrompt from 'ee/ai/duo_agentic_chat/plugins/goal/components/message_goal_prompt.vue';
import { PROMPT_COMPOSER_ACTIONS } from 'ee/ai/duo_agentic_chat/constants';
import { DuoChatPluginRegistry } from 'ee/ai/duo_agentic_chat/services/plugin_registry';
import { slashCommands } from 'ee/ai/duo_agentic_chat/services/plugin_capabilities/slash_commands';

describe('goalPlugin', () => {
  const PROJECT_ID = 'gid://gitlab/Project/1';

  const apolloReturning = (...consumers) => ({
    query: jest.fn().mockResolvedValue({
      data: { aiCatalogConfiguredItems: { nodes: consumers } },
    }),
  });

  const configuredFlow = apolloReturning({ id: 'gid://gitlab/Ai::Catalog::ItemConsumer/7' });

  const commandsOf = (apollo, duoChatContext = { projectId: PROJECT_ID }) =>
    slashCommands.resolve([goalPlugin], { apollo, duoChatContext });

  it('is filed under a name that identifies it in plugin reports', () => {
    expect(goalPlugin.name).toBe('goal');
  });

  // Guards the shipped plugin against its own contract: the registry drops anything
  // malformed, so a broken descriptor would otherwise only show up as a missing widget.
  it('satisfies the plugin contract', () => {
    const registry = new DuoChatPluginRegistry();

    registry.registerPlugin(goalPlugin);

    expect(registry.plugins).toEqual([goalPlugin]);
  });

  describe('the goal turn in the transcript', () => {
    const [widget] = goalPlugin.messageWidgets;

    it('renders it with MessageGoalPrompt', () => {
      expect(goalPlugin.messageWidgets).toEqual([
        { matchMessage: expect.any(Function), component: MessageGoalPrompt },
      ]);
    });

    it('claims a user prompt that was sent as a goal', () => {
      expect(widget.matchMessage({ role: 'user', content: '/goal ship it' })).toBe(true);
    });

    it('leaves an ordinary prompt to duo-ui', () => {
      expect(widget.matchMessage({ role: 'user', content: 'ship it' })).toBe(false);
    });

    // The command is offered only where the flow is configured; a turn that already ran
    // as a goal has to keep reading as one either way.
    it('claims it whether or not the flow is still configured', async () => {
      expect(widget.matchMessage({ role: 'user', content: '/goal ship it' })).toBe(true);
      await expect(commandsOf(apolloReturning())).resolves.toEqual([]);
    });
  });

  it('offers one command, which the capability accepts', async () => {
    await expect(commandsOf(configuredFlow)).resolves.toEqual([
      {
        label: '/goal',
        value: '/goal',
        description: 'Work until a goal is met',
        startOnly: true,
        action: PROMPT_COMPOSER_ACTIONS.START_GOAL,
      },
    ]);
  });

  // `argumentHint` would be dead data here, not a missing requirement: `START_GOAL`
  // strips `/goal` out of the text the moment it runs, so the command is recorded for
  // one tick and never again, and nothing would ever read the hint. The composer asks
  // for the goal off `goalFlow` instead, with a sentence of its own.
  it('asks for no argument of its own', async () => {
    const [command] = await commandsOf(configuredFlow);

    expect(command.argumentHint).toBeUndefined();
  });

  // The only thing tying the command to the mode it starts.
  it('names the action the composer starts goal mode for', async () => {
    const [command] = await commandsOf(configuredFlow);

    expect(command.action).toBe('startGoal');
  });

  describe('when goal mode cannot run', () => {
    // Offering a command that could only fail is worse than offering none.
    it('offers nothing when no Developer flow is configured', async () => {
      await expect(commandsOf(apolloReturning())).resolves.toEqual([]);
    });

    it('offers nothing, and asks nothing, without a project', async () => {
      const apollo = apolloReturning();

      await expect(commandsOf(apollo, {})).resolves.toEqual([]);
      expect(apollo.query).not.toHaveBeenCalled();
    });

    // A mount with no state manager above it passes no context at all.
    it('offers nothing without a chat context', async () => {
      await expect(slashCommands.resolve([goalPlugin], {})).resolves.toEqual([]);
    });
  });
});
