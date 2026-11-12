# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Ai::BulkUpdateAiToolRules, feature_category: :ai_agents do
  include GraphqlHelpers

  # Specs enable flags by default; pin the shipped fail-open background default.
  before do
    stub_feature_flags(duo_workflow_background_fail_closed: false)
  end

  subject(:mutation) { described_class }

  it { is_expected.to have_graphql_name('BulkUpdateAiToolRules') }

  it { is_expected.to have_graphql_fields(:results, :errors, :client_mutation_id) }

  it 'has expected arguments' do
    is_expected.to have_graphql_arguments(
      :full_path,
      :project_path,
      :tool_rules,
      :client_mutation_id
    )
  end

  describe '#resolve', :clean_gitlab_redis_rate_limiting do
    let_it_be(:namespace) { create(:group) }
    let_it_be(:owner) { create(:user, owner_of: namespace) }
    let_it_be(:developer) { create(:user, developer_of: namespace) }

    let(:current_user) { owner }
    let(:mutation_params) do
      {
        full_path: namespace.full_path,
        tool_rules: [
          { tool_id: 'create_issue', web_access: 'ask' },
          { tool_id: 'read_file', web_access: 'deny' }
        ]
      }
    end

    subject(:result) { resolve(described_class, args: mutation_params, ctx: { current_user: current_user }) }

    before do
      ::Ai::ToolRules::Registry.instance_variable_set(:@all_tool_names, nil)
      ::Ai::ToolRules::Registry.instance_variable_set(:@catalog_tool_names, nil)
      ::Ai::ToolRules::Registry.instance_variable_set(:@action_type_for, nil)
      allow(Gitlab::Audit::Auditor).to receive(:audit)
    end

    context 'when the user is not authorized' do
      let(:current_user) { developer }

      it 'raises ResourceNotAvailable' do
        expect(result).to be_a(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end

      it 'does not count the call against the rate limit' do
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original

        result

        expect(Gitlab::ApplicationRateLimiter).not_to have_received(:throttled?)
          .with(described_class::RATE_LIMIT_KEY, anything)
      end
    end

    context 'when the namespace does not exist' do
      let(:mutation_params) do
        { full_path: 'non/existent', tool_rules: [{ tool_id: 'create_issue', web_access: 'ask' }] }
      end

      it 'raises ResourceNotAvailable' do
        expect(result).to be_a(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    context 'when namespace is not a root namespace' do
      let_it_be(:subgroup) { create(:group, parent: namespace) }
      let(:mutation_params) do
        { full_path: subgroup.full_path, tool_rules: [{ tool_id: 'create_issue', web_access: 'ask' }] }
      end

      it 'raises ResourceNotAvailable' do
        expect(result).to be_a(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    context 'when current_user cannot access the project' do
      let_it_be(:other_namespace) { create(:group) }
      let_it_be(:private_project) { create(:project, :private, namespace: other_namespace) }

      let(:mutation_params) do
        {
          full_path: namespace.full_path,
          project_path: private_project.full_path,
          tool_rules: [{ tool_id: 'create_issue', web_access: 'ask' }]
        }
      end

      it 'raises ResourceNotAvailable' do
        expect(result).to be_a(Gitlab::Graphql::Errors::ResourceNotAvailable)
      end
    end

    context 'when the user is over the rate limit' do
      before do
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(described_class::RATE_LIMIT_KEY, scope: { user: owner })
          .and_return(true)
      end

      it 'raises before writing or auditing anything', :aggregate_failures do
        expect(Gitlab::Audit::Auditor).not_to receive(:audit)

        expect { result }
          .to raise_error(RateLimitedService::RateLimitedError)
          .and not_change { Ai::ToolRule.count }
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(ai_tool_rules_bulk_update_rate_limit: false)
        end

        it 'does not consult the limiter and writes the rules' do
          expect { result }.to change { Ai::ToolRule.count }.by(2)
          expect(Gitlab::ApplicationRateLimiter).not_to have_received(:throttled?)
            .with(described_class::RATE_LIMIT_KEY, anything)
        end
      end
    end

    context 'when the user is authorized' do
      it 'creates rules and returns results', :aggregate_failures do
        expect(result[:results].length).to eq(2)
        expect(result[:errors]).to be_empty
      end

      it 'persists all rules in a single upsert', :aggregate_failures do
        expect(::Ai::ToolRule).to receive(:upsert_all).once.and_call_original
        expect { result }.to change { Ai::ToolRule.count }.by(2)
      end

      it 'returns correct values for each rule', :aggregate_failures do
        create_issue_result = result[:results].find { |r| r[:tool_id] == 'create_issue' }
        read_file_result = result[:results].find { |r| r[:tool_id] == 'read_file' }

        expect(create_issue_result[:tool_rule][:web_access]).to eq('ask')
        expect(create_issue_result[:errors]).to be_empty
        expect(read_file_result[:tool_rule][:web_access]).to eq('deny')
        expect(read_file_result[:errors]).to be_empty
      end

      it 'returns effective values with the configured and default values', :aggregate_failures do
        create_issue_result = result[:results].find { |r| r[:tool_id] == 'create_issue' }

        expect(create_issue_result[:tool_rule]).to include(
          web_access: 'ask',
          local_access: 'ask',
          background_access: 'allow',
          configured_access: { web_access: 'ask', local_access: nil, background_access: nil },
          default_access: { web_access: 'ask', local_access: 'ask', background_access: 'allow' }
        )
      end

      context 'when the namespace opted into background fail-closed' do
        before do
          stub_feature_flags(duo_workflow_background_fail_closed: namespace)
        end

        it 'returns deny as the background default' do
          create_issue_result = result[:results].find { |r| r[:tool_id] == 'create_issue' }

          expect(create_issue_result[:tool_rule][:default_access]).to include(background_access: 'deny')
        end
      end

      it 'emits a single bulk audit event' do
        expect(Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(
            name: 'ai_tool_rules_bulk_updated',
            author: owner,
            scope: namespace,
            additional_details: hash_including(
              tool_count: 2,
              tool_names: %w[create_issue read_file]
            )
          )
        )

        result
      end

      context 'when background_access is provided' do
        let(:mutation_params) do
          {
            full_path: namespace.full_path,
            tool_rules: [{ tool_id: 'create_issue', background_access: 'deny' }]
          }
        end

        it 'persists and returns background_access', :aggregate_failures do
          create_issue_result = result[:results].find { |r| r[:tool_id] == 'create_issue' }

          expect(create_issue_result[:tool_rule][:background_access]).to eq('deny')
          rule = Ai::ToolRule.find_by(namespace_id: namespace.id, tool_name: 'create_issue')
          expect(rule.background_access).to eq('deny')
        end

        context 'when the rule already exists (on_duplicate update)' do
          before do
            create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', background_access: :allow)
          end

          it 'updates background_access via the upsert on_duplicate clause' do
            expect { result }.to change {
              Ai::ToolRule.find_by(namespace_id: namespace.id, tool_name: 'create_issue').background_access
            }.from('allow').to('deny')
          end
        end
      end

      context 'when every submitted rule equals the stored rule' do
        let_it_be(:stored_create_issue) do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :ask)
        end

        let_it_be(:stored_read_file) do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'read_file', web_access: :deny)
        end

        it 'does not write, does not audit, and still returns both rules', :aggregate_failures do
          expect(::Ai::ToolRule).not_to receive(:upsert_all)
          expect(Gitlab::Audit::Auditor).not_to receive(:audit)

          expect(result[:errors]).to be_empty
          expect(result[:results].map { |r| r[:tool_id] }).to match_array(%w[create_issue read_file])
          expect(result[:results].map { |r| r[:errors] }).to all(be_empty)
          expect(result[:results].map { |r| r[:tool_rule][:web_access] }).to match_array(%w[ask deny])
        end

        it 'leaves updated_at untouched' do
          expect { result }.not_to change { stored_create_issue.reload.updated_at }
        end

        it 'runs one lookup regardless of how many rules are submitted' do
          one_rule = mutation_params.merge(tool_rules: mutation_params[:tool_rules].first(1))

          lookups = [one_rule, mutation_params].map do |params|
            recorder = ActiveRecord::QueryRecorder.new do
              resolve(described_class, args: params, ctx: { current_user: current_user })
            end

            recorder.log.count { |sql| sql.start_with?('SELECT "ai_tool_rules"') }
          end

          expect(lookups).to all(eq(1))
        end
      end

      context 'when the same tool appears twice in the payload' do
        let_it_be(:stored) { create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :ask) }

        let(:mutation_params) do
          {
            full_path: namespace.full_path,
            tool_rules: [
              { tool_id: 'create_issue', web_access: 'ask' },
              { tool_id: 'create_issue', web_access: 'deny' }
            ]
          }
        end

        it 'fails the batch instead of skipping the matching entry', :aggregate_failures do
          expect(result[:errors]).to include('Failed to save tool rules')
          expect(result[:results].map { |r| r[:errors] }).to all(include('Failed to save rule'))
        end
      end

      context 'when one of two rules is unchanged' do
        let_it_be(:stored) { create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :ask) }

        it 'upserts and audits only the changed row', :aggregate_failures do
          expect(::Ai::ToolRule).to receive(:upsert_all)
            .with([hash_including(tool_name: 'read_file')], anything)
            .and_call_original
          expect(Gitlab::Audit::Auditor).to receive(:audit).with(
            hash_including(additional_details: hash_including(tool_count: 1, tool_names: %w[read_file]))
          )

          expect { result }.to change { Ai::ToolRule.count }.by(1)
          expect(result[:results].map { |r| r[:tool_id] }).to match_array(%w[create_issue read_file])
          expect(result[:results].map { |r| r[:errors] }).to all(be_empty)
        end
      end

      context 'when the payload omits a surface the stored rule sets' do
        let_it_be(:stored) do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :ask, local_access: :deny)
        end

        let(:mutation_params) do
          { full_path: namespace.full_path, tool_rules: [{ tool_id: 'create_issue', web_access: 'ask' }] }
        end

        it 'counts as a change and clears that surface', :aggregate_failures do
          expect(Gitlab::Audit::Auditor).to receive(:audit)

          expect { result }.to change { stored.reload.local_access }.from('deny').to(nil)
        end
      end

      context 'when a rule already exists for a tool' do
        let_it_be(:existing_rule) do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :allow)
        end

        it 'updates the existing rule without creating a new one' do
          existing_rule

          expect { result }.to change { Ai::ToolRule.count }.by(1)
        end

        it 'returns the updated values' do
          create_issue_result = result[:results].find { |r| r[:tool_id] == 'create_issue' }

          expect(create_issue_result[:tool_rule][:web_access]).to eq('ask')
        end
      end

      context 'when a first-party rule is left over from duo_cli_first_party_tools being on' do
        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'mcp__duo__review', local_access: :deny)
          stub_feature_flags(duo_cli_first_party_tools: false)
        end

        it 'still saves the other rules', :aggregate_failures do
          expect(result[:results]).to all(include(errors: []))
          expect(Ai::ToolRule.find_by(namespace: namespace, tool_name: 'read_file').web_access).to eq('deny')
        end
      end

      context 'when one tool_id is unknown' do
        let(:mutation_params) do
          {
            full_path: namespace.full_path,
            tool_rules: [
              { tool_id: 'create_issue', web_access: 'ask' },
              { tool_id: 'invented_tool', web_access: 'deny' }
            ]
          }
        end

        it 'returns an error for the unknown tool and succeeds for the known one', :aggregate_failures do
          create_issue_result = result[:results].find { |r| r[:tool_id] == 'create_issue' }
          invented_result = result[:results].find { |r| r[:tool_id] == 'invented_tool' }

          expect(create_issue_result[:errors]).to be_empty
          expect(create_issue_result[:tool_rule]).to be_present
          expect(invented_result[:errors]).to include('invented_tool is not a known tool name')
          expect(invented_result[:tool_rule]).to be_nil
        end

        it 'only persists the valid rule' do
          expect { result }.to change { Ai::ToolRule.count }.by(1)
        end

        it 'does not include the unknown tool in the audit event' do
          expect(Gitlab::Audit::Auditor).to receive(:audit).with(
            hash_including(
              additional_details: hash_including(
                tool_count: 1,
                tool_names: ['create_issue']
              )
            )
          )

          result
        end
      end

      context 'when a tool_id is a first-party client tool' do
        let(:mutation_params) do
          { full_path: namespace.full_path, tool_rules: [{ tool_id: 'mcp__duo__review', web_access: 'deny' }] }
        end

        it 'saves it with the MCP source when the flag is on for the root group', :aggregate_failures do
          stub_feature_flags(duo_cli_first_party_tools: namespace)

          expect(result[:results].first).to include(errors: [])
          expect(result[:results].first[:tool_rule]).to include(category: 'Duo CLI', web_access: 'deny')
          expect(Ai::ToolRule.find_by(namespace: namespace, tool_name: 'mcp__duo__review').tool_source).to eq('mcp')
        end

        it 'rejects it when the flag is on only for another root group' do
          stub_feature_flags(duo_cli_first_party_tools: create(:group))

          expect(result[:results].first[:errors]).to include('mcp__duo__review is not a known tool name')
        end
      end

      context 'when all tool_ids are unknown' do
        let(:mutation_params) do
          {
            full_path: namespace.full_path,
            tool_rules: [{ tool_id: 'invented_tool', web_access: 'deny' }]
          }
        end

        it 'does not emit an audit event' do
          expect(Gitlab::Audit::Auditor).not_to receive(:audit).with(
            hash_including(name: 'ai_tool_rules_bulk_updated')
          )

          result
        end

        it 'does not persist any rules' do
          expect { result }.not_to change { Ai::ToolRule.count }
        end
      end

      context 'when project_path is provided' do
        let_it_be(:project) { create(:project, namespace: namespace) }

        let(:mutation_params) do
          {
            full_path: namespace.full_path,
            project_path: project.full_path,
            tool_rules: [{ tool_id: 'create_issue', web_access: 'ask' }]
          }
        end

        it 'creates a project-scoped rule', :aggregate_failures do
          result
          rule = Ai::ToolRule.find_by(namespace_id: namespace.id, project_id: project.id, tool_name: 'create_issue')

          expect(rule).to be_present
          expect(rule.web_access).to eq('ask')
        end

        context 'when the namespace rule already equals the project input' do
          let_it_be(:namespace_rule) do
            create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :ask)
          end

          it 'still writes and audits the project row', :aggregate_failures do
            expect(Gitlab::Audit::Auditor).to receive(:audit)

            expect { result }.to change { Ai::ToolRule.for_project(project.id).count }.by(1)
          end
        end

        context 'when the project row already equals the input' do
          let_it_be(:project_rule) do
            create(:ai_tool_rule, namespace: namespace, project: project, tool_name: 'create_issue', web_access: :ask)
          end

          it 'writes nothing and audits nothing', :aggregate_failures do
            expect(::Ai::ToolRule).not_to receive(:upsert_all)
            expect(Gitlab::Audit::Auditor).not_to receive(:audit)

            expect(result[:results].first[:errors]).to be_empty
          end
        end

        context 'when a row from another namespace shares the project id' do
          let_it_be(:other_namespace) { create(:group) }
          let_it_be(:stale_rule) do
            rule = build(:ai_tool_rule, namespace: other_namespace, project: project, tool_name: 'create_issue',
              web_access: :ask)
            rule.save!(validate: false)
            rule
          end

          it 'is not mistaken for this namespace row' do
            expect { result }
              .to change { Ai::ToolRule.for_namespace_and_projects(namespace.id, [project.id]).count }.by(1)
          end
        end

        context 'when the database raises an error' do
          before do
            allow(::Ai::ToolRule).to receive(:upsert_all).and_raise(ActiveRecord::StatementInvalid.new('DB error'))
          end

          it 'reports the project row as failed', :aggregate_failures do
            expect(result[:errors]).to include('Failed to save tool rules')
            expect(result[:results].first[:errors]).to include('Failed to save rule')
          end
        end

        it 'does not affect namespace-level rules' do
          result

          expect(Ai::ToolRule.for_namespace(namespace.id).find_by(tool_name: 'create_issue')).to be_nil
        end

        context 'when the namespace sets another access type' do
          before do
            create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :allow,
              local_access: :deny)
          end

          it 'returns the effective values across both rules', :aggregate_failures do
            tool_rule = result[:results].first[:tool_rule]

            expect(tool_rule).to include(web_access: 'ask', local_access: 'deny')
            expect(tool_rule[:configured_access]).to include(web_access: 'ask', local_access: nil)
          end
        end
      end

      context 'when project_path does not exist' do
        let(:mutation_params) do
          {
            full_path: namespace.full_path,
            project_path: 'non/existent',
            tool_rules: [{ tool_id: 'create_issue', web_access: 'ask' }]
          }
        end

        it 'raises ResourceNotAvailable' do
          expect(result).to be_a(Gitlab::Graphql::Errors::ResourceNotAvailable)
        end
      end

      context 'when project does not belong to the namespace' do
        let_it_be(:other_namespace) { create(:group) }
        let_it_be(:other_project) { create(:project, namespace: other_namespace) }

        let(:mutation_params) do
          {
            full_path: namespace.full_path,
            project_path: other_project.full_path,
            tool_rules: [{ tool_id: 'create_issue', web_access: 'ask' }]
          }
        end

        it 'raises ResourceNotAvailable' do
          expect(result).to be_a(Gitlab::Graphql::Errors::ResourceNotAvailable)
        end
      end

      context 'when no access surface is provided' do
        let(:mutation_params) do
          {
            full_path: namespace.full_path,
            tool_rules: [{ tool_id: 'create_issue' }]
          }
        end

        it 'returns a per-item error', :aggregate_failures do
          expect(result[:results].first[:errors]).to include(
            'At least one of web_access, local_access, or background_access must be provided'
          )
          expect(result[:results].first[:tool_rule]).to be_nil
        end

        it 'does not persist any rules' do
          expect { result }.not_to change { Ai::ToolRule.count }
        end
      end

      context 'when the database raises an error' do
        before do
          allow(::Ai::ToolRule).to receive(:upsert_all)
            .and_raise(ActiveRecord::StatementInvalid.new('DB error'))
        end

        it 'returns a top-level error and per-item errors for valid inputs', :aggregate_failures do
          expect(result[:errors]).to include('Failed to save tool rules')
          expect(result[:results].length).to eq(2)
          expect(result[:results]).to all(satisfy { |r|
            r[:errors].include?('Failed to save rule') && r[:tool_rule].nil?
          })
        end

        it 'does not emit an audit event' do
          expect(Gitlab::Audit::Auditor).not_to receive(:audit).with(
            hash_including(name: 'ai_tool_rules_bulk_updated')
          )

          result
        end

        it 'tracks the exception' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
            instance_of(ActiveRecord::StatementInvalid),
            hash_including(namespace_id: namespace.id)
          )

          result
        end

        context 'when one submitted rule equals the stored rule' do
          let_it_be(:stored) do
            create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', web_access: :ask)
          end

          it 'reports the unchanged rule as saved and only the changed one as failed', :aggregate_failures do
            by_tool = result[:results].index_by { |r| r[:tool_id] }

            expect(result[:errors]).to include('Failed to save tool rules')
            expect(by_tool['create_issue'][:errors]).to be_empty
            expect(by_tool['create_issue'][:tool_rule][:web_access]).to eq('ask')
            expect(by_tool['read_file'][:errors]).to include('Failed to save rule')
          end
        end
      end
    end
  end
end
