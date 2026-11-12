# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Ai::DapFactory::Configuration, feature_category: :dap_triggers do
  def stage(key, **overrides)
    attributes = {
      key: key, skipped: false, status: key.capitalize, start_mode: described_class::AUTOMATED,
      exit_mode: described_class::AUTOMATED, flow: 1, mark_merge_requests_ready: false
    }

    described_class::Stage.new(**attributes.merge(overrides))
  end

  # Mirrors Validator: every stage of STAGES is present, in order, and the ones left out are skipped.
  def configuration(*stages)
    by_key = stages.index_by(&:key)
    all = described_class::STAGES.map { |key| by_key[key] || described_class::Stage.skipped(key) }

    described_class.new(factory_name: 'Factory', stages: all, review: nil)
  end

  describe 'Stage' do
    it 'reports a skipped stage as neither automated start nor automated exit' do
      skipped = described_class::Stage.skipped('build')

      expect(skipped).to be_skipped
      expect(skipped).not_to be_automated_start
      expect(skipped).not_to be_automated_exit
      expect(skipped).not_to be_triggered
    end

    it 'reads the start and exit modes' do
      manual = stage('build', start_mode: described_class::MANUAL, exit_mode: described_class::MANUAL)

      expect(stage('build')).to be_automated_start
      expect(stage('build')).to be_automated_exit
      expect(manual).not_to be_automated_start
      expect(manual).not_to be_automated_exit
    end

    it 'is triggered only with an automated start and a flow' do
      expect(stage('build')).to be_triggered
      expect(stage('build', flow: nil)).not_to be_triggered
      expect(stage('build', start_mode: described_class::MANUAL)).not_to be_triggered
    end

    it 'excludes a merge request driven stage from the status triggered ones' do
      expect(stage('review')).to be_merge_request_driven
      expect(stage('review')).to be_triggered
      expect(stage('review')).not_to be_status_triggered
      expect(stage('build')).to be_status_triggered
    end

    it 'marks the stages that run before a work item has a workplan as intake' do
      expect(stage('triage')).to be_intake
      expect(stage('plan')).to be_intake
      expect(stage('build')).not_to be_intake
    end
  end

  describe '#stage' do
    let(:config) { configuration(stage('build')) }

    it 'finds a stage by a string or a symbol key' do
      expect(config.stage('build').key).to eq('build')
      expect(config.stage(:build).key).to eq('build')
    end

    it 'returns nil for a key that is not a stage' do
      expect(config.stage(:nonsense)).to be_nil
    end
  end

  describe '#next_stage_after' do
    let(:config) { configuration(stage('triage'), stage('build')) }

    it 'skips over the stages the factory leaves out' do
      expect(config.next_stage_after(:triage).key).to eq('build')
    end

    it 'returns nil when every later stage is skipped' do
      expect(config.next_stage_after(:build)).to be_nil
    end

    it 'returns nil for a key that is not a stage' do
      expect(config.next_stage_after(:nonsense)).to be_nil
    end
  end

  describe '#triggered_stages' do
    it 'keeps only the stages that start a flow' do
      config = configuration(stage('triage'), stage('build', flow: nil))

      expect(config.triggered_stages.map(&:key)).to eq(%w[triage])
    end
  end

  describe '#status_on_finish_for' do
    it 'returns the status of the next stage that is not skipped' do
      config = configuration(stage('build'), stage('review'))

      expect(config.status_on_finish_for(config.stage(:build))).to eq('Review')
    end

    it 'returns nil when the stage exits manually' do
      config = configuration(stage('build', exit_mode: described_class::MANUAL), stage('review'))

      expect(config.status_on_finish_for(config.stage(:build))).to be_nil
    end

    it 'returns nil when no later stage is in the factory' do
      config = configuration(stage('build'))

      expect(config.status_on_finish_for(config.stage(:build))).to be_nil
    end
  end
end
