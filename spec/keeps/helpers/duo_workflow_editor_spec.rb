# frozen_string_literal: true

require 'spec_helper'
require './keeps/helpers/duo_workflow_editor'

RSpec.describe Keeps::Helpers::DuoWorkflowEditor, feature_category: :tooling do
  let(:logger) { instance_double(Gitlab::Housekeeper::Logger, puts: nil) }
  let(:create_url) { "#{described_class::API_HOST}#{described_class::CREATE_WORKFLOW_PATH}" }
  let(:graphql_url) { "#{described_class::API_HOST}#{described_class::GRAPHQL_PATH}" }

  subject(:editor) { described_class.new(logger: logger, timeout_seconds: 120) }

  before do
    stub_env('DUO_WORKFLOW_API_TOKEN', 'a-token')
    allow(editor).to receive(:sleep)
  end

  def stub_status(status, status_group: 'ACTIVE')
    node = { id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/7', status: status, statusGroup: status_group }

    stub_request(:post, graphql_url).to_return(
      status: 200,
      body: { data: { duoWorkflowWorkflows: { nodes: [node] } } }.to_json
    )
  end

  describe '#initialize' do
    it 'raises when no token is available' do
      stub_env('DUO_WORKFLOW_API_TOKEN', nil)
      stub_env('HOUSEKEEPER_GITLAB_API_TOKEN', nil)

      expect { described_class.new(logger: logger) }.to raise_error(ArgumentError, /token/)
    end

    context 'with the timeout from the environment' do
      it 'uses the value when it is a positive integer' do
        stub_env('DUO_WORKFLOW_TIMEOUT_SECONDS', '60')

        expect(described_class.new(logger: logger).timeout_seconds).to eq(60)
      end

      it 'falls back to the default when the value is malformed' do
        stub_env('DUO_WORKFLOW_TIMEOUT_SECONDS', 'not-a-number')

        expect(described_class.new(logger: logger).timeout_seconds).to eq(described_class::DEFAULT_TIMEOUT_SECONDS)
      end
    end
  end

  describe '#run' do
    before do
      stub_request(:post, create_url).to_return(status: 200, body: { id: 7 }.to_json)
    end

    it 'starts a session on the given branch' do
      stub_status('FINISHED')

      editor.run(goal: 'Remove the flag', source_branch: 'a-branch')

      matcher = a_request(:post, create_url).with do |req|
        body = Gitlab::Json::SafeParser.parse(req.body)

        body['goal'] == 'Remove the flag' &&
          body['source_branch'] == 'a-branch' &&
          body['environment'] == described_class::ENVIRONMENT &&
          body['start_workflow'] == true
      end

      expect(matcher).to have_been_made
    end

    it 'requests a non-interactive session so it never blocks on tool-call approval' do
      stub_status('FINISHED')

      editor.run(goal: 'Remove the flag', source_branch: 'a-branch')

      matcher = a_request(:post, create_url).with do |req|
        body = Gitlab::Json::SafeParser.parse(req.body)

        body['agent_privileges'] == described_class::AGENT_PRIVILEGES &&
          body['pre_approved_agent_privileges'] == described_class::AGENT_PRIVILEGES &&
          body['allow_agent_to_request_user'] == false
      end

      expect(matcher).to have_been_made
    end

    %w[TOOL_CALL_APPROVAL_REQUIRED INPUT_REQUIRED PLAN_APPROVAL_REQUIRED].each do |status|
      it "returns false without waiting when the session parks in #{status}" do
        stub_status(status, status_group: 'AWAITING_INPUT')

        expect(editor.run(goal: 'Remove the flag', source_branch: 'a-branch')).to be(false)
      end
    end

    it 'returns false without waiting when the session is paused' do
      stub_status('PAUSED', status_group: 'PAUSED')

      expect(editor.run(goal: 'Remove the flag', source_branch: 'a-branch')).to be(false)
    end

    it 'returns true when the session finishes' do
      stub_status('FINISHED')

      expect(editor.run(goal: 'Remove the flag', source_branch: 'a-branch')).to be(true)
    end

    %w[FAILED STOPPED].each do |status|
      it "returns false when the session ends as #{status}" do
        stub_status(status)

        expect(editor.run(goal: 'Remove the flag', source_branch: 'a-branch')).to be(false)
      end
    end

    it 'returns false when the session does not reach a terminal status before the timeout' do
      stub_status('RUNNING')
      editor = described_class.new(logger: logger, timeout_seconds: 0)

      expect(editor.run(goal: 'Remove the flag', source_branch: 'a-branch')).to be(false)
    end

    it 'returns false when the session cannot be started' do
      stub_request(:post, create_url).to_return(status: 403, body: 'Forbidden')

      expect(editor.run(goal: 'Remove the flag', source_branch: 'a-branch')).to be(false)
      expect(a_request(:post, graphql_url)).not_to have_been_made
    end

    it 'returns false when the create response body cannot be parsed' do
      stub_request(:post, create_url).to_return(status: 200, body: 'not json')

      expect(editor.run(goal: 'Remove the flag', source_branch: 'a-branch')).to be(false)
      expect(a_request(:post, graphql_url)).not_to have_been_made
    end

    it 'does not raise when a poll response body cannot be parsed' do
      stub_request(:post, graphql_url).to_return(status: 200, body: 'not json')
      editor = described_class.new(logger: logger, timeout_seconds: 0)

      expect(editor.run(goal: 'Remove the flag', source_branch: 'a-branch')).to be(false)
    end

    it 'keeps polling when a poll request raises a transient network error' do
      node = { id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/7', status: 'FINISHED', statusGroup: 'COMPLETED' }
      stub_request(:post, graphql_url)
        .to_raise(Errno::ECONNRESET)
        .then
        .to_return(status: 200, body: { data: { duoWorkflowWorkflows: { nodes: [node] } } }.to_json)

      expect(editor.run(goal: 'Remove the flag', source_branch: 'a-branch')).to be(true)
    end

    context 'when a poll does not settle the session' do
      let(:finished) do
        { data: { duoWorkflowWorkflows: { nodes: [
          { id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/7', status: 'FINISHED', statusGroup: 'COMPLETED' }
        ] } } }.to_json
      end

      it 'keeps polling while the session is still running' do
        running = { data: { duoWorkflowWorkflows: { nodes: [
          { id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/7', status: 'RUNNING', statusGroup: 'ACTIVE' }
        ] } } }.to_json
        stub_request(:post, graphql_url)
          .to_return(status: 200, body: running)
          .then
          .to_return(status: 200, body: finished)

        expect(editor.run(goal: 'Remove the flag', source_branch: 'a-branch')).to be(true)
        expect(a_request(:post, graphql_url)).to have_been_made.twice
      end

      it 'logs and keeps polling when a poll request is rejected' do
        stub_request(:post, graphql_url)
          .to_return(status: 502, body: 'Bad Gateway')
          .then
          .to_return(status: 200, body: finished)

        expect(editor.run(goal: 'Remove the flag', source_branch: 'a-branch')).to be(true)
        expect(logger).to have_received(:puts).with('Failed to poll Duo Workflow session 7: 502 Bad Gateway')
      end

      it 'keeps polling when a poll response cannot be parsed' do
        stub_request(:post, graphql_url)
          .to_return(status: 200, body: 'not json')
          .then
          .to_return(status: 200, body: finished)

        expect(editor.run(goal: 'Remove the flag', source_branch: 'a-branch')).to be(true)
      end
    end
  end
end
