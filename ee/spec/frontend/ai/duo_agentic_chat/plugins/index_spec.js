import { initializePlugins } from 'ee/ai/duo_agentic_chat/plugins';
import { startFlowPlugin } from 'ee/ai/duo_agentic_chat/plugins/start_flow';
import { basicChatCommandsPlugin } from 'ee/ai/duo_agentic_chat/plugins/basic_chat_commands';
import { compactPlugin } from 'ee/ai/duo_agentic_chat/plugins/compact';
import { tierAccessDeniedPlugin } from 'ee/ai/duo_agentic_chat/plugins/tier_access_denied';
import { flowCommandsPlugin } from 'ee/ai/duo_agentic_chat/plugins/flow_commands';
import { goalPlugin } from 'ee/ai/duo_agentic_chat/plugins/goal';
import { attachmentsPlugin } from 'ee/ai/duo_agentic_chat/plugins/attachments';
import { DuoChatPluginRegistry } from 'ee/ai/duo_agentic_chat/services/plugin_registry';

describe('initializePlugins', () => {
  const BUNDLED = [
    startFlowPlugin,
    basicChatCommandsPlugin,
    compactPlugin,
    tierAccessDeniedPlugin,
    flowCommandsPlugin,
  ];

  const registerWith = (features = {}) => {
    window.gon = { features };
    const registry = new DuoChatPluginRegistry();

    initializePlugins(registry);

    return registry.plugins;
  };

  it('registers every bundled plugin into the given registry', () => {
    expect(registerWith()).toEqual([...BUNDLED, goalPlugin]);
  });

  describe('a plugin behind a feature flag', () => {
    // Registered in place rather than appended: duo-ui takes the first matching widget,
    // and a goal turn that also sent files has to reach the attachments widget, which
    // draws the goal badge itself.
    it('registers the attachment chips behind their flag, ahead of the goal command', () => {
      expect(registerWith({ dapWebChatFileAttachments: true })).toEqual([
        ...BUNDLED,
        attachmentsPlugin,
        goalPlugin,
      ]);
      expect(registerWith({ dapWebChatFileAttachments: false })).not.toContain(attachmentsPlugin);
    });

    it('is left out when there are no flags at all', () => {
      window.gon = undefined;
      const registry = new DuoChatPluginRegistry();

      initializePlugins(registry);

      expect(registry.plugins).toEqual([...BUNDLED, goalPlugin]);
    });
  });
});
