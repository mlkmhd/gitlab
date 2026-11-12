# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'CiRunnerManager upgradeStatus cached attributes', :clean_gitlab_redis_cache,
  feature_category: :fleet_visibility do
  include GraphqlHelpers
  include RunnerReleasesHelper

  let_it_be(:admin) { create(:admin) }
  let_it_be(:runner) { create(:ci_runner) }
  let_it_be(:managers) { create_list(:ci_runner_machine, 3, runner: runner, version: '14.0.0') }

  let(:query) do
    <<~GRAPHQL
      {
        runners(first: 100) {
          nodes {
            managers(first: 100) {
              nodes { upgradeStatus }
            }
          }
        }
      }
    GRAPHQL
  end

  before do
    stub_licensed_features(runner_upgrade_management: true)
    stub_runner_releases(%w[14.0.0 14.1.0])

    managers.each { |manager| manager.cache_attributes(version: '14.1.0') }
  end

  # The recorder sees only commands that are sent one by one, not pipelined commands.
  def run_query
    RedisCommands::Recorder.new(pattern: 'cache:Ci::RunnerManager:') do
      post_graphql(query, current_user: admin)
    end
  end

  def upgrade_statuses
    graphql_data_at(:runners, :nodes, :managers, :nodes, :upgradeStatus)
  end

  it 'reads the cached version of all managers with one batched read', :aggregate_failures do
    expect(RedisCacheable::CachedAttributesReader).to receive(:preload).once.and_wrap_original do |original, readers|
      expect(readers.size).to eq(managers.size)

      original.call(readers)
    end

    recorder = run_query

    expect(graphql_errors).to be_nil
    expect(upgrade_statuses).to all(eq('NOT_AVAILABLE'))
    expect(recorder.by_command('get')).to be_empty
  end

  context 'when ci_batch_runner_manager_cached_attributes is disabled' do
    before do
      stub_feature_flags(ci_batch_runner_manager_cached_attributes: false)
    end

    it 'reads the cached version of each manager separately', :aggregate_failures do
      expect(RedisCacheable::CachedAttributesReader).not_to receive(:preload)

      recorder = run_query

      expect(graphql_errors).to be_nil
      expect(upgrade_statuses).to all(eq('NOT_AVAILABLE'))
      expect(recorder.by_command('get').size).to eq(managers.size)
    end
  end
end
