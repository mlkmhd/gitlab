import { s__ } from '~/locale';

// Keyed by the raw `agentType` wire values. Entries without an `icon` render an
// initial-letter avatar instead of a sprite.
export const CLIENT_TYPES = {
  'claude-code': { name: s__('AgentArtifacts|Claude Code') },
  opencode: { name: s__('AgentArtifacts|OpenCode') },
  cursor: { name: s__('AgentArtifacts|Cursor') },
  codex: { name: s__('AgentArtifacts|Codex') },
};

// `tanuki` is the GitLab logo, as the MCP server isn't a Duo session.
export const MCP_CLIENT_TYPE = {
  name: s__('AgentArtifacts|GitLab MCP server'),
  icon: 'tanuki',
};

export const DEFAULT_CLIENT_TYPE = {
  name: s__('AgentArtifacts|GitLab Duo'),
  icon: 'tanuki-ai',
};
