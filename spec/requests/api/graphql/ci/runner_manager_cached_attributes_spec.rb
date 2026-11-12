# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'CiRunnerManager cached attributes', :clean_gitlab_redis_cache,
  feature_category: :fleet_visibility do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }
  let_it_be(:runners) { create_list(:ci_runner, 2) }
  let_it_be(:managers) do
    runners.flat_map { |runner| create_list(:ci_runner_machine, 3, runner: runner, version: '14.0.0') }
  end

  let(:fields) { 'version' }
  let(:page_size) { 2 }
  let(:query) do
    <<~GRAPHQL
      {
        runners(first: 100) {
          nodes {
            managers(first: #{page_size}) {
              nodes { id #{fields} }
            }
          }
        }
      }
    GRAPHQL
  end

  before do
    managers.each do |manager|
      manager.cache_attributes(version: '14.0.1', contacted_at: Time.current, creation_state: 'finished')
    end
  end

  # The recorder sees only commands that are sent one by one, not pipelined commands.
  def run_query
    RedisCommands::Recorder.new(pattern: 'cache:Ci::RunnerManager:') do
      post_graphql(query, current_user: admin)
    end
  end

  def manager_nodes
    graphql_data_at(:runners, :nodes).flat_map { |runner| runner.dig('managers', 'nodes') }
  end

  def expect_one_preload_of(size)
    expect(RedisCacheable::CachedAttributesReader).to receive(:preload).once.and_wrap_original do |original, readers|
      expect(readers.size).to eq(size)

      original.call(readers)
    end
  end

  it 'reads the cached attributes of the managers on the page with one batched read', :aggregate_failures do
    expect_one_preload_of(runners.size * page_size)

    recorder = run_query

    expect(graphql_errors).to be_nil
    expect(manager_nodes.size).to eq(runners.size * page_size)
    expect(manager_nodes.pluck('version')).to all(eq('14.0.1'))
    expect(recorder.by_command('get')).to be_empty
  end

  context 'with more managers on the page' do
    let(:page_size) { 3 }

    it 'still reads them with one batched read', :aggregate_failures do
      expect_one_preload_of(managers.size)

      recorder = run_query

      expect(manager_nodes.size).to eq(managers.size)
      expect(recorder.by_command('get')).to be_empty
    end
  end

  context 'when several fields read the cached attributes' do
    let(:fields) { 'version contactedAt ipAddress revision platformName architectureName executorName status' }

    it 'reads them with one batched read', :aggregate_failures do
      expect_one_preload_of(runners.size * page_size)

      recorder = run_query

      expect(graphql_errors).to be_nil
      expect(recorder.by_command('get')).to be_empty
    end
  end

  context 'when the same manager is also loaded through a job' do
    let_it_be(:project) { create(:project) }
    let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
    let_it_be(:build) { create(:ci_build, pipeline: pipeline, runner_manager: managers.first) }

    let(:query) do
      <<~GRAPHQL
        {
          project(fullPath: "#{project.full_path}") {
            pipeline(iid: "#{pipeline.iid}") {
              jobs { nodes { runnerManager { version } } }
            }
          }
          runners(first: 100) { nodes { managers(first: 100) { nodes { version } } } }
        }
      GRAPHQL
    end

    it 'reads the cached attributes of each manager once and returns the cached values', :aggregate_failures do
      expect_one_preload_of(managers.size)

      recorder = run_query

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:project, :pipeline, :jobs, :nodes, :runnerManager, :version)).to eq(['14.0.1'])
      expect(manager_nodes.pluck('version')).to all(eq('14.0.1'))
      expect(recorder.by_command('get')).to be_empty
    end
  end

  context 'when ci_batch_runner_manager_cached_attributes is disabled' do
    before do
      stub_feature_flags(ci_batch_runner_manager_cached_attributes: false)
    end

    it 'reads the cached attributes of each manager separately', :aggregate_failures do
      expect(RedisCacheable::CachedAttributesReader).not_to receive(:preload)

      recorder = run_query

      expect(graphql_errors).to be_nil
      expect(manager_nodes.pluck('version')).to all(eq('14.0.1'))
      expect(recorder.by_command('get').size).to eq(manager_nodes.size)
    end
  end
end
