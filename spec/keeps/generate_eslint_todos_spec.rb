# frozen_string_literal: true

require 'spec_helper'
require './keeps/generate_eslint_todos'

RSpec.describe Keeps::GenerateEslintTodos, time_travel_to: '2026-11-12', feature_category: :tooling do
  subject(:keep) { described_class.new }

  let(:roulette) { instance_double(Keeps::Helpers::ReviewerRoulette) }
  let(:git_status) { '' }

  before do
    allow(Keeps::Helpers::ReviewerRoulette).to receive(:instance).and_return(roulette)
    allow(roulette).to receive(:random_reviewer_for)
      .with('maintainer::frontend', identifiers: %w[GenerateEslintTodos 2026 11])
      .and_return('reviewer')
    allow(::Gitlab::Housekeeper::Shell).to receive(:execute).with(*described_class::GENERATOR)
    allow(::Gitlab::Housekeeper::Shell).to receive(:execute)
      .with('git', 'status', '--short', described_class::ESLINT_TODO_DIR)
      .and_return(git_status)
  end

  def run_keep
    changes = []
    keep.each_identified_change do |change|
      keep.make_change!(change)
      changes << change
    end
    changes
  end

  it 'regenerates every todo file' do
    run_keep

    expect(::Gitlab::Housekeeper::Shell).to have_received(:execute)
      .with('node', 'scripts/frontend/generate_eslint_todo_list.mjs', '--all')
  end

  context 'when a todo file changed' do
    let(:git_status) { ' M .eslint_todo/vue-html-self-closing.mjs' }

    it 'populates the change' do
      expect(run_keep).to contain_exactly(have_attributes(
        identifiers: %w[GenerateEslintTodos 2026 11],
        title: described_class::TITLE,
        description: described_class::DESCRIPTION,
        labels: described_class::LABELS,
        changed_files: ['.eslint_todo'],
        reviewers: ['reviewer']
      ))
    end
  end

  context 'when no todo file changed' do
    it 'leaves the change unpopulated' do
      expect(run_keep).to contain_exactly(have_attributes(title: nil, description: nil))
    end
  end
end
