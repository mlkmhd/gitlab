# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Ai::ToolRules::ToolPresenter, feature_category: :duo_agent_platform do
  describe '.display_name_for' do
    it 'converts snake_case tool names to human readable format' do
      expect(described_class.display_name_for('create_issue')).to eq('Create Issue')
      expect(described_class.display_name_for('run_git_command')).to eq('Run Git Command')
      expect(described_class.display_name_for('read_file')).to eq('Read File')
    end

    it 'handles acronyms correctly' do
      expect(described_class.display_name_for('ci_linter')).to eq('CI Linter')
      expect(described_class.display_name_for('ascp_create_scan')).to eq('ASCP Create Scan')
      expect(described_class.display_name_for('gitlab_graphql')).to eq('GitLab GraphQL')
      expect(described_class.display_name_for('run_glql_query')).to eq('Run GLQL Query')
      expect(described_class.display_name_for('submit_mr_review')).to eq('Submit MR Review')
      expect(described_class.display_name_for('list_mr_discussions')).to eq('List MR Discussions')
      expect(described_class.display_name_for(
        'post_sast_fp_analysis_to_gitlab'
      )).to eq('Post SAST False Positive Analysis to GitLab')
    end

    it 'handles the double underscore edge case' do
      expect(described_class.display_name_for('gitlab__user_search')).to eq('GitLab User Search')
    end
  end

  describe '.default_access_for' do
    it 'returns ask for a write tool, with background relaxed to allow' do
      expect(described_class.default_access_for('create_issue')).to eq(
        web_access: 'ask', local_access: 'ask', background_access: 'allow'
      )
    end

    it 'returns allow for a preapproved read tool' do
      read_tool = Ai::ToolRules::Registry::PRIVILEGE_GROUP_MAPPING[:read_only_gitlab].first

      expect(described_class.default_access_for(read_tool)).to eq(
        web_access: 'allow', local_access: 'allow', background_access: 'allow'
      )
    end

    it 'returns allow for a first-party client tool only when the namespace has it', :aggregate_failures do
      first_party_tools = Ai::ToolRules::FirstPartyTools.new(%w[mcp__duo__review])

      expect(described_class.default_access_for('mcp__duo__review', first_party_tools: first_party_tools)).to eq(
        web_access: 'allow', local_access: 'allow', background_access: 'allow'
      )
      expect(described_class.default_access_for('mcp__duo__review')).to eq(
        web_access: 'ask', local_access: 'ask', background_access: 'allow'
      )
    end

    context 'when fail-closed' do
      it 'shows deny on background for a write tool and allow for a read tool', :aggregate_failures do
        read_tool = Ai::ToolRules::Registry::PRIVILEGE_GROUP_MAPPING[:read_only_gitlab].first

        expect(described_class.default_access_for('create_issue', fail_closed: true)).to eq(
          web_access: 'ask', local_access: 'ask', background_access: 'deny'
        )
        expect(described_class.default_access_for(read_tool, fail_closed: true)[:background_access]).to eq('allow')
      end
    end
  end

  describe '.tool_rule_for' do
    let(:project_rule) { { background_access: 'allow' } }

    def background_access(namespace_rule:, fail_closed:)
      described_class.tool_rule_for('run_command', namespace_rule: namespace_rule, project_rule: project_rule,
        project_scoped: true, fail_closed: fail_closed)[:background_access]
    end

    it 'shows the project allow without fail-closed' do
      expect(background_access(namespace_rule: nil, fail_closed: false)).to eq('allow')
    end

    it 'shows deny when the project allow would loosen the fail-closed default' do
      expect(background_access(namespace_rule: nil, fail_closed: true)).to eq('deny')
    end

    it 'shows the project allow when the namespace rule allows the tool' do
      expect(background_access(namespace_rule: { background_access: 'allow' }, fail_closed: true)).to eq('allow')
    end

    it 'leaves the web and local values to the rules' do
      row = described_class.tool_rule_for('run_command', namespace_rule: nil,
        project_rule: { web_access: 'allow', local_access: 'allow' }, project_scoped: true, fail_closed: true)

      expect(row).to include(web_access: 'allow', local_access: 'allow')
    end
  end
end
