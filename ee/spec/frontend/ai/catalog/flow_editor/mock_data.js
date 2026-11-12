// The agents the references query resolves to, as the editor extension consumes them.
export const AGENTS = [
  { id: '43', name: 'Generator' },
  { id: '47', name: 'Interpreter' },
];

// The same agents as the GraphQL query returns them, before the apollo update maps them.
export const AGENTS_QUERY_NODES = [
  { id: 'gid://gitlab/Ai::Catalog::Item/43', name: 'Generator' },
  { id: 'gid://gitlab/Ai::Catalog::Item/47', name: 'Interpreter' },
];

// A flow with agents in the include block and in a subagents list, for the include context helpers.
export const FLOW_INCLUDE_BLOCKS = `version: "v1"
environment: ambient
include:
  - source: ai-catalog
    item_type: agent
    item_id: "43"
  - source: ai-catalog
    item_type: agent
    item_id: 47
  - source: workspace
    item_type: agent_template
    item_id: "*"
components:
  - name: "main"
    type: AgentComponent
    subagents:
      - source: ai-catalog
        item_type: agent
        item_id: "43"
      - helper
    toolset: []
`;

// A flow with resolved, unresolved, empty and non-catalog references, for the editor extension.
export const FLOW_AGENT_REFERENCES = `include:
  - source: ai-catalog
    item_type: agent
    item_id: "43"
  - source: ai-catalog
    item_type: agent
    item_id: "99"
  - source: ai-catalog
    item_type: agent
    item_id: 
  - source: workspace
    item_type: agent_template
    item_id: "7"
components:
  - name: "main"
    type: AgentComponent
    subagents:
      - source: ai-catalog
        item_type: agent
        item_id: ""
      - source: ai-catalog
        item_type: agent
        item_id: "43"
`;
