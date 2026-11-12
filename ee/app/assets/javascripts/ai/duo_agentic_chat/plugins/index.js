import { startFlowPlugin } from './start_flow';
import { basicChatCommandsPlugin } from './basic_chat_commands';
import { compactPlugin } from './compact';
import { tierAccessDeniedPlugin } from './tier_access_denied';
import { flowCommandsPlugin } from './flow_commands';
import { goalPlugin } from './goal';
import { attachmentsPlugin } from './attachments';

// One ordered list: registration order decides which widget duo-ui picks, so a flagged
// plugin has to keep its place rather than be appended once the flag is on. The flag is
// kept out of the plugins themselves so a plugin stays a plain description of what it
// contributes, with nothing to stub when testing one.
const PLUGINS = [
  { plugin: startFlowPlugin },
  { plugin: basicChatCommandsPlugin },
  { plugin: compactPlugin },
  { plugin: tierAccessDeniedPlugin },
  { plugin: flowCommandsPlugin },
  // Ahead of goal: duo-ui takes the first widget that matches, and a goal turn with
  // files needs the attachments widget, which draws the goal badge as well.
  { plugin: attachmentsPlugin, flag: 'dapWebChatFileAttachments' },
  { plugin: goalPlugin },
];

/**
 * Registers every plugin bundled with the chat. Must run before the panel mounts:
 * the registry is not reactive, so anything registered later is not picked up.
 *
 * @param {import('../services/plugin_registry').DuoChatPluginRegistry} registry
 */
export function initializePlugins(registry) {
  PLUGINS.filter(({ flag }) => !flag || window.gon?.features?.[flag]).forEach(({ plugin }) =>
    registry.registerPlugin(plugin),
  );
}
