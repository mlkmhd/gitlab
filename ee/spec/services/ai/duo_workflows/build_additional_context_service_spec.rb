# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Ai::DuoWorkflows::BuildAdditionalContextService, feature_category: :duo_agent_platform do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, group: group) }
  let_it_be(:current_user) { create(:user, developer_of: project) }
  let_it_be(:service_account) { create(:user, :service_account) }

  let(:source_branch) { nil }
  let(:session_url) { 'http://example.com/-/automate/agent-sessions/1' }
  let(:ref) { 'refs/workloads/1' }
  let(:event_type) { nil }
  let(:triggering_conversation) { nil }
  let(:additional_context) { nil }
  let(:foundational_flow) { nil }
  let(:goal) { nil }

  subject(:execute) do
    described_class.new(
      standard_context_params: {
        project: project,
        current_user: current_user,
        service_account: service_account,
        source_branch: source_branch,
        session_url: session_url,
        ref: ref
      },
      trigger_params: {
        event_type: event_type,
        triggering_conversation: triggering_conversation
      },
      additional_context: additional_context,
      foundational_flow: foundational_flow,
      goal: goal
    ).execute
  end

  def standard_context_envelope(context)
    context.find { |envelope| envelope["Category"] == "agent_platform_standard_context" }
  end

  def trigger_context_envelope(context)
    context.find { |envelope| envelope["Category"] == "agent_platform_trigger_context" }
  end

  def resource_context_envelope(context)
    context.find { |envelope| envelope["Category"] == "agent_platform_resource_context" }
  end

  it 'returns a successful response' do
    expect(execute).to be_a(ServiceResponse)
    expect(execute).to be_success
  end

  describe 'standard context' do
    it 'adds a single agent_platform_standard_context envelope with a JSON-encoded Content string' do
      context = execute.payload[:context]
      envelope = standard_context_envelope(context)

      expect(envelope).to be_present
      expect(envelope["Content"]).to be_a(String)
      expect(::Gitlab::Json::SafeParser.parse(envelope["Content"])).to eq(
        "workload_branch" => ref,
        "primary_branch" => project.default_branch_or_main,
        "session_owner_id" => current_user.id.to_s,
        "session_owner_username" => current_user.username,
        "service_account_name" => service_account.username,
        "session_url" => session_url
      )
      expect(envelope["metadata"]).to eq("version" => described_class::DWS_STANDARD_CONTEXT_VERSION)
    end

    context 'when source_branch exists in the repository' do
      let(:source_branch) { 'feature-branch' }

      before do
        project.repository.create_branch(source_branch, project.default_branch)
      end

      it 'uses source_branch as primary_branch' do
        content = ::Gitlab::Json::SafeParser.parse(standard_context_envelope(execute.payload[:context])["Content"])

        expect(content["primary_branch"]).to eq(source_branch)
      end
    end

    context 'when source_branch does not exist in the repository' do
      let(:source_branch) { 'non-existent-branch' }

      it 'falls back to the default branch as primary_branch' do
        content = ::Gitlab::Json::SafeParser.parse(standard_context_envelope(execute.payload[:context])["Content"])

        expect(content["primary_branch"]).to eq(project.default_branch_or_main)
      end
    end

    context 'when source_branch is nil' do
      let(:source_branch) { nil }

      it 'falls back to the default branch as primary_branch without raising' do
        content = ::Gitlab::Json::SafeParser.parse(standard_context_envelope(execute.payload[:context])["Content"])

        expect(content["primary_branch"]).to eq(project.default_branch_or_main)
      end
    end
  end

  context 'when standard_context_params is nil' do
    subject(:execute) do
      described_class.new(
        trigger_params: { event_type: 'mention' },
        foundational_flow: Ai::Catalog::FoundationalFlow.bl_security_experimental,
        goal: '1'
      ).execute
    end

    it 'builds neither the standard context nor the business logic security envelope' do
      expect(execute.payload[:context].pluck("Category")).to contain_exactly("agent_platform_trigger_context")
    end
  end

  describe 'trigger context' do
    context 'when neither event_type nor triggering_conversation is set' do
      it 'does not add an agent_platform_trigger_context envelope' do
        context = execute.payload[:context]

        expect(trigger_context_envelope(context)).to be_nil
      end
    end

    context 'when event_type and triggering_conversation are set' do
      let(:event_type) { 'mention' }
      let(:triggering_conversation) { 'explain this finding' }

      it 'adds an agent_platform_trigger_context envelope with a JSON-encoded Content string' do
        envelope = trigger_context_envelope(execute.payload[:context])

        expect(envelope["Content"]).to be_a(String)
        expect(::Gitlab::Json::SafeParser.parse(envelope["Content"])).to eq(
          'event_type' => 'mention',
          'triggering_conversation' => 'explain this finding'
        )
        expect(envelope["metadata"]).to eq("version" => described_class::DWS_CONTEXT_VERSION)
      end
    end

    context 'when only event_type is set' do
      let(:event_type) { 'assign' }

      it 'serializes only the set keys' do
        envelope = trigger_context_envelope(execute.payload[:context])

        expect(::Gitlab::Json::SafeParser.parse(envelope["Content"])).to eq('event_type' => 'assign')
      end
    end
  end

  describe 'additional_context handling' do
    context 'when additional_context is nil' do
      let(:additional_context) { nil }

      it 'returns only the standard context envelope' do
        context = execute.payload[:context]

        expect(context.map { |e| e["Category"] }).to contain_exactly("agent_platform_standard_context")
      end
    end

    context 'when additional_context contains unrelated envelopes' do
      let(:additional_context) do
        [{ Category: "agent_user_environment", Content: "some content", Metadata: "{}" }]
      end

      it 'preserves them ahead of the Rails-controlled envelopes' do
        context = execute.payload[:context]

        expect(context.map { |envelope| envelope["Category"] || envelope[:Category] }).to eq(
          %w[agent_user_environment agent_platform_standard_context]
        )
      end

      it 'does not mutate the caller-provided array' do
        expect { execute }.not_to change { additional_context.size }
      end
    end

    context 'when additional_context contains a colliding agent_platform_standard_context envelope' do
      let(:additional_context) do
        [{ "Category" => "agent_platform_standard_context", "Content" => ::Gitlab::Json.dump({ "key" => "value" }) }]
      end

      it 'drops the caller-provided envelope and keeps only the Rails-controlled one' do
        context = execute.payload[:context]
        standard_envelopes = context.select { |envelope| envelope["Category"] == "agent_platform_standard_context" }

        expect(standard_envelopes.size).to eq(1)
        expect(::Gitlab::Json::SafeParser.parse(standard_envelopes.first["Content"])).not_to eq({ "key" => "value" })
      end
    end

    context 'when a colliding agent_platform_standard_context envelope is symbol-keyed' do
      let(:additional_context) do
        [{ Category: "agent_platform_standard_context", Content: ::Gitlab::Json.dump({ "key" => "value" }) }]
      end

      it 'drops the caller-provided envelope and keeps only the Rails-controlled one' do
        context = execute.payload[:context]

        expect(context.size).to eq(1)
        expect(::Gitlab::Json::SafeParser.parse(context.first["Content"])).not_to eq({ "key" => "value" })
      end
    end

    context 'when additional_context contains a colliding agent_platform_client_context envelope' do
      let(:additional_context) do
        [{ "Category" => "agent_platform_client_context", "Content" => ::Gitlab::Json.dump({ "content" => "x" }) }]
      end

      it 'drops the caller-provided envelope' do
        expect(execute.payload[:context].pluck("Category")).not_to include("agent_platform_client_context")
      end

      context 'and client_context is set' do
        subject(:execute) do
          described_class.new(additional_context: additional_context, client_context: 'Slack context').execute
        end

        it 'keeps only the Rails-controlled envelope' do
          envelope = execute.payload[:context].sole

          expect(envelope).to eq(
            "Category" => "agent_platform_client_context",
            "Content" => ::Gitlab::Json.dump({ "content" => "Slack context" }),
            "metadata" => { "version" => described_class::DWS_CLIENT_CONTEXT_VERSION }
          )
        end
      end
    end

    context 'when a colliding agent_platform_trigger_context envelope is symbol-keyed' do
      let(:additional_context) do
        [{ Category: "agent_platform_trigger_context", Content: ::Gitlab::Json.dump({ "event_type" => "spoofed" }) }]
      end

      it 'drops the caller-provided envelope' do
        context = execute.payload[:context]

        expect(context.map { |envelope| envelope["Category"] }).not_to include("agent_platform_trigger_context")
      end

      context 'and trigger params are set' do
        let(:event_type) { 'mention' }

        it 'keeps only the Rails-controlled envelope' do
          context = execute.payload[:context]
          trigger_envelopes = context.select { |envelope| envelope["Category"] == "agent_platform_trigger_context" }

          expect(trigger_envelopes.size).to eq(1)
          expect(::Gitlab::Json::SafeParser.parse(trigger_envelopes.first["Content"])).to eq('event_type' => 'mention')
        end
      end
    end

    context 'when additional_context contains a colliding agent_platform_trigger_context envelope' do
      let(:additional_context) do
        [{
          "Category" => "agent_platform_trigger_context",
          "Content" => ::Gitlab::Json.dump({ "event_type" => "spoofed" })
        }]
      end

      it 'drops the caller-provided envelope' do
        context = execute.payload[:context]

        expect(context.map { |envelope| envelope["Category"] }).not_to include("agent_platform_trigger_context")
      end

      context 'and trigger params are set' do
        let(:event_type) { 'mention' }
        let(:triggering_conversation) { 'explain this finding' }

        it 'keeps only the Rails-controlled envelope' do
          context = execute.payload[:context]
          trigger_envelopes = context.select { |envelope| envelope["Category"] == "agent_platform_trigger_context" }

          expect(trigger_envelopes.size).to eq(1)
          expect(::Gitlab::Json::SafeParser.parse(trigger_envelopes.first["Content"])).to eq(
            'event_type' => 'mention',
            'triggering_conversation' => 'explain this finding'
          )
        end
      end
    end
  end

  describe 'resource context' do
    subject(:execute) do
      described_class.new(
        standard_context_params: {
          project: project,
          current_user: current_user,
          service_account: service_account,
          source_branch: source_branch,
          session_url: session_url,
          ref: ref
        },
        trigger_params: {},
        additional_context: additional_context,
        resource: resource
      ).execute
    end

    context 'when resource is nil' do
      let(:resource) { nil }

      it 'does not add an agent_platform_resource_context envelope' do
        expect(resource_context_envelope(execute.payload[:context])).to be_nil
      end
    end

    context 'when resource is a MergeRequest' do
      let(:resource) { create(:merge_request, source_project: project) }

      it 'adds an agent_platform_resource_context envelope' do
        envelope = resource_context_envelope(execute.payload[:context])

        expect(envelope).to be_present
        expect(envelope["metadata"]).to eq("version" => described_class::DWS_RESOURCE_CONTEXT_VERSION)
        content = ::Gitlab::Json::SafeParser.parse(envelope["Content"])
        expect(content["resource_type"]).to eq("merge_request")
        expect(content["resource_id"]).to eq(resource.iid.to_s)
      end
    end

    context 'when additional_context contains a colliding agent_platform_resource_context envelope' do
      let(:resource) { create(:merge_request, source_project: project) }
      let(:additional_context) do
        [{ "Category" => "agent_platform_resource_context",
           "Content" => ::Gitlab::Json.dump({ "resource_type" => "spoofed" }) }]
      end

      it 'drops the caller-provided envelope and keeps only the Rails-controlled one' do
        context = execute.payload[:context]
        resource_envelopes = context.select { |e| e["Category"] == "agent_platform_resource_context" }

        expect(resource_envelopes.size).to eq(1)
        content = ::Gitlab::Json::SafeParser.parse(resource_envelopes.first["Content"])
        expect(content["resource_type"]).to eq("merge_request")
      end
    end
  end

  describe 'flow context' do
    let(:resource) { create(:merge_request, source_project: project) }
    let(:flow_category) { 'agent_platform_recommend_reviewers_context' }
    let(:foundational_flow) do
      instance_double(
        ::Ai::Catalog::FoundationalFlow,
        reference: 'recommend_reviewers/v1',
        flow_config_id: 'recommend_reviewers',
        context_category_alias: nil,
        resolve_additional_context_for: { 'candidates' => [] }
      )
    end

    let(:goal) { 'Recommend reviewers' }
    let(:standard_context_params) do
      {
        project: project,
        current_user: current_user,
        service_account: service_account,
        source_branch: source_branch,
        session_url: session_url,
        ref: ref
      }
    end

    subject(:execute) do
      described_class.new(
        standard_context_params: standard_context_params,
        additional_context: additional_context,
        resource: resource,
        foundational_flow: foundational_flow,
        goal: goal
      ).execute
    end

    it 'appends the envelopes the flow resolves for the resource', :aggregate_failures do
      envelope = execute.payload[:context].find { |e| e['Category'] == flow_category }

      expect(foundational_flow).to have_received(:resolve_additional_context_for).with(
        runtime_context: have_attributes(
          project: project,
          resource: resource,
          goal: goal,
          primary_branch: project.default_branch_or_main
        )
      )
      expect(::Gitlab::Json::SafeParser.parse(envelope['Content'])).to eq('candidates' => [])
    end

    context 'without standard_context_params' do
      let(:standard_context_params) { nil }

      it 'resolves the flow context without a project or primary branch' do
        execute

        expect(foundational_flow).to have_received(:resolve_additional_context_for).with(
          runtime_context: have_attributes(project: nil, resource: resource, goal: goal, primary_branch: nil)
        )
      end
    end

    context 'when additional_context contains a colliding envelope' do
      let(:additional_context) do
        [{ 'Category' => flow_category, 'Content' => ::Gitlab::Json.dump({ 'candidates' => %w[spoofed] }) }]
      end

      it 'drops the caller-provided envelope and keeps only the flow-controlled one' do
        envelopes = execute.payload[:context].select { |e| e['Category'] == flow_category }

        expect(envelopes.size).to eq(1)
        expect(::Gitlab::Json::SafeParser.parse(envelopes.first['Content'])).to eq('candidates' => [])
      end
    end

    context 'when the flow sets a context_category_alias and the caller sends that category' do
      let(:foundational_flow) do
        instance_double(
          ::Ai::Catalog::FoundationalFlow,
          reference: 'code_review/v1',
          flow_config_id: 'code_review',
          context_category_alias: 'code_review_context',
          resolve_additional_context_for: { 'last_reviewed_head_sha' => 'abc123' }
        )
      end

      let(:additional_context) do
        [{ 'Category' => 'code_review_context',
           'Content' => ::Gitlab::Json.dump({ 'last_reviewed_head_sha' => 'spoofed' }) }]
      end

      it 'drops the caller-provided envelope and keeps only the flow-controlled one' do
        envelopes = execute.payload[:context].select { |e| e['Category'] == 'code_review_context' }

        expect(envelopes.size).to eq(1)
        expect(::Gitlab::Json::SafeParser.parse(envelopes.first['Content'])).to eq('last_reviewed_head_sha' => 'abc123')
      end
    end
  end

  describe 'categories of other foundational flows' do
    let(:additional_context) do
      %w[code_review_context agent_platform_risk_classification_context agent_platform_developer_context]
        .map { |category| { 'Category' => category, 'Content' => ::Gitlab::Json.dump({ 'spoofed' => true }) } }
    end

    it 'drops caller-provided envelopes for every category a foundational flow can send' do
      expect(execute.payload[:context].pluck('Category')).to contain_exactly('agent_platform_standard_context')
    end
  end
end
