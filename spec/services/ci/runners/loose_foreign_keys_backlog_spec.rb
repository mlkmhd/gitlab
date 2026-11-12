# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::Runners::LooseForeignKeysBacklog, feature_category: :runner_core do
  let(:backlog) { described_class.new }

  before do
    create_list(:ci_runner_machine, 4).each(&:delete)
    # Pending records of other tables, including ci_runners, are not counted.
    create(:ci_runner).delete
    create(:ci_build).delete
  end

  describe '#pending_count' do
    it 'counts pending records of runner managers' do
      expect(backlog.pending_count(limit: 10)).to eq(4)
    end

    it 'counts at most the limit' do
      expect(backlog.pending_count(limit: 2)).to eq(2)
    end

    it 'returns 0 without an active partition' do
      allow(LooseForeignKeys::DeletedRecord.partitioning_strategy).to receive(:active_partition).and_return(nil)

      expect(backlog.pending_count(limit: 10)).to eq(0)
    end

    it 'does not count processed records' do
      Gitlab::Database::SharedModel.using_connection(Ci::ApplicationRecord.connection) do
        LooseForeignKeys::DeletedRecord.for_table(described_class::TABLES).update_all(status: :processed)
      end

      expect(backlog.pending_count(limit: 10)).to eq(0)
    end
  end

  describe '#over_limit?' do
    it 'is true when more records than the limit are pending' do
      expect(backlog.over_limit?(3)).to be(true)
    end

    it 'is false when at most the limit is pending' do
      expect(backlog.over_limit?(4)).to be(false)
    end

    it 'is true when the count times out' do
      allow(backlog).to receive(:pending_count).and_raise(ActiveRecord::QueryCanceled)

      expect(backlog.over_limit?(100)).to be(true)
    end
  end
end
