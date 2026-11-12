# frozen_string_literal: true

require 'spec_helper'

# Per-row reads on a page of sessions: a field selected on every row of
# `duoWorkflowWorkflows` must cost the same for one row as for a page. Fields
# that still read per row are pending on the issue that batches them.
RSpec.describe 'Reading a page of Duo Workflows', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:ai_settings, freeze: false) { create(:namespace_ai_settings, duo_workflow_mcp_enabled: true) }
  let_it_be(:group, freeze: false) { create(:group, ai_settings: ai_settings) }
  let_it_be(:project, freeze: false) { create(:project, :public, group: group) }
  let_it_be(:user, freeze: false) { create(:user, developer_of: group) }

  let(:current_user) { user }
  let(:variables) { { project_path: project.full_path } }
  let(:query) { graphql_query_for('duoWorkflowWorkflows', variables, fields) }

  let(:checkpoint_tables) { /FROM "p_duo_workflows_checkpoint(s|_headers|_blobs)"/ }
  let(:legacy_checkpoint_table) { /FROM "p_duo_workflows_checkpoints"/ }
  let(:incremental_tables) { /FROM "p_duo_workflows_checkpoint_(headers|blobs)"/ }

  before do
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(any_args).and_return(true)
    # rubocop:disable RSpec/AnyInstanceOf -- not the next instance
    allow_any_instance_of(User).to receive_messages(allowed_to_use?: true, allowed_to_use_for_resource?: true)
    # rubocop:enable RSpec/AnyInstanceOf
  end

  # A session whose channel values live in headers and blobs, as
  # CreateCheckpointService writes them: a chain of two checkpoints with a
  # status and a chat-log delta each.
  def create_incremental_session(name)
    workflow = create(:duo_workflows_workflow, project: project, user: user, incremental_checkpoints_enabled: true)
    channel_values = { 'status' => 'Planning', 'ui_chat_log' => [] }

    [["#{name}-ts-1", nil, '1', 'Planning'], ["#{name}-ts-2", "#{name}-ts-1", '2', 'Execution']]
      .each do |thread_ts, parent_ts, version, status|
      create(:duo_workflows_checkpoint_header, workflow: workflow, thread_ts: thread_ts, parent_ts: parent_ts,
        checkpoint: { 'v' => 1, 'channel_versions' => {}, 'versions_seen' => {}, 'channel_values' => channel_values })
      create(:duo_workflows_checkpoint_blob, workflow: workflow, thread_ts: thread_ts, channel: 'status',
        version: version, step_action: 'conversation', data: Zlib::Deflate.deflate(Gitlab::Json.dump(status)))
      chat_delta = [{ 'content' => "#{name} #{status}", 'message_type' => 'user' }]
      create(:duo_workflows_checkpoint_blob, workflow: workflow, thread_ts: thread_ts, channel: 'ui_chat_log',
        version: version, step_action: 'conversation', data: Zlib::Deflate.deflate(Gitlab::Json.dump(chat_delta)))
    end

    workflow
  end

  # A session written before incremental checkpoints: one full checkpoint row.
  def create_legacy_session
    workflow = create(:duo_workflows_workflow, project: project, user: user)
    create(:duo_workflows_checkpoint, :ui_chat_log, workflow: workflow, project: project)
    workflow
  end

  def create_page_of_sessions
    create_incremental_session(SecureRandom.hex(4))
    create_legacy_session
  end

  def returned_nodes
    graphql_data.dig('duoWorkflowWorkflows', 'nodes')
  end

  # One row of each kind is the control, two more of each is the page.
  def record_control
    create_page_of_sessions
    post_graphql(query, current_user: current_user) # warm up per-request caches

    recorder = ActiveRecord::QueryRecorder.new(skip_cached: false) do
      post_graphql(query, current_user: current_user)
    end

    expect(graphql_errors).to be_nil
    expect(returned_nodes.size).to eq(2)
    recorder
  end

  def expect_flat_reads(control, on_tables)
    expect { post_graphql(query, current_user: current_user) }
      .not_to exceed_all_query_limit(control).for_query(on_tables)
    expect(graphql_errors).to be_nil
    expect(returned_nodes.size).to eq(6)
  end

  context 'when the page selects the newest and oldest checkpoint of every row' do
    let(:fields) { 'nodes { id latestCheckpoint { threadTs } firstCheckpoint { threadTs } }' }

    it 'loads the headers of the incremental sessions in page-level queries', :aggregate_failures do
      control = record_control

      2.times { create_page_of_sessions }

      expect_flat_reads(control, incremental_tables)
      expect(returned_nodes.map { |node| node.dig('latestCheckpoint', 'threadTs') }).to all(be_present)
      expect(returned_nodes.map { |node| node.dig('firstCheckpoint', 'threadTs') }).to all(be_present)
    end

    it 'loads the checkpoint rows of the legacy sessions in page-level queries', :aggregate_failures do
      control = record_control

      2.times { create_page_of_sessions }

      expect_flat_reads(control, legacy_checkpoint_table)
    end
  end

  context 'when the page selects the channel values of the newest checkpoint' do
    let(:fields) { 'nodes { id latestCheckpoint { checkpoint compressedCheckpoint } }' }

    it 'folds the blobs of every incremental session in page-level queries', :aggregate_failures,
      pending: 'https://gitlab.com/gitlab-org/gitlab/-/work_items/637904' do
      control = record_control

      2.times { create_page_of_sessions }

      expect_flat_reads(control, incremental_tables)
      expect(returned_nodes.map { |node| node.dig('latestCheckpoint', 'checkpoint') }).to all(be_present)
    end
  end

  context 'when the page selects executionStatus' do
    let(:fields) { 'nodes { id latestCheckpoint { executionStatus } }' }

    it 'folds the status channel of every row in page-level queries', :aggregate_failures,
      pending: 'https://gitlab.com/gitlab-org/gitlab/-/work_items/628075' do
      control = record_control

      2.times { create_page_of_sessions }

      expect_flat_reads(control, checkpoint_tables)
      expect(returned_nodes.map { |node| node.dig('latestCheckpoint', 'executionStatus') }).to all(be_present)
    end
  end

  context 'when the page selects the executor log URLs' do
    let(:fields) { 'nodes { id lastExecutorLogsUrl allExecutorLogsUrls }' }

    it 'loads the workloads of every row in page-level queries', :aggregate_failures,
      pending: 'https://gitlab.com/gitlab-org/gitlab/-/work_items/628076' do
      control = record_control

      2.times { create_page_of_sessions }

      expect_flat_reads(control, /FROM "(duo_workflows_workloads|p_ci_workloads)"/)
    end
  end

  context 'when the page selects mcpEnabled' do
    let(:fields) { 'nodes { id mcpEnabled }' }

    it 'reads the root namespace settings once for the page', :aggregate_failures do
      control = record_control

      2.times { create_page_of_sessions }

      expect_flat_reads(control, /FROM "(namespaces|namespace_ai_settings)"/)
      expect(returned_nodes.pluck('mcpEnabled')).to all(be(true))
    end
  end
end
