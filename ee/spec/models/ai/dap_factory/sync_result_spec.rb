# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DapFactory::SyncResult, :aggregate_failures, :use_clean_rails_memory_store_caching, feature_category: :dap_triggers do
  let_it_be(:project) { create(:project) }

  let(:synced_at) { Time.zone.parse('2026-11-02T10:00:00Z') }
  let(:result) do
    described_class.new(status: 'partial', commit_sha: 'abc123', synced_at: synced_at,
      errors: [{ 'path' => nil, 'code' => 'failed', 'message' => 'no' }], summary: { 'created' => %w[build] })
  end

  describe '.for' do
    it 'returns nil when nothing was saved for the project' do
      expect(described_class.for(project)).to be_nil
    end

    it 'returns what was last saved for the project' do
      result.save(project) # rubocop:disable Rails/SaveBang -- not an ActiveRecord save

      expect(described_class.for(project)).to have_attributes(
        status: 'partial', commit_sha: 'abc123', synced_at: synced_at,
        errors: [{ 'path' => nil, 'code' => 'failed', 'message' => 'no' }], summary: { 'created' => %w[build] }
      )
    end

    it 'keeps only the latest result' do
      result.save(project) # rubocop:disable Rails/SaveBang -- not an ActiveRecord save
      described_class.new(status: 'synced', commit_sha: 'def456', synced_at: synced_at)
        .save(project) # rubocop:disable Rails/SaveBang -- not an ActiveRecord save

      expect(described_class.for(project)).to have_attributes(status: 'synced', commit_sha: 'def456', errors: [])
    end

    it 'is scoped to the project' do
      result.save(project) # rubocop:disable Rails/SaveBang -- not an ActiveRecord save

      expect(described_class.for(create(:project))).to be_nil
    end

    it 'reads a result saved with other attributes, filling in defaults' do
      Rails.cache.write(described_class.cache_key(project), { 'status' => 'failed', 'bogus' => 1 })

      expect(described_class.for(project)).to have_attributes(
        status: 'failed', commit_sha: nil, synced_at: nil, errors: [], summary: {}
      )
    end

    it 'gives each result its own default errors and summary' do
      Rails.cache.write(described_class.cache_key(project), { 'status' => 'failed' })

      described_class.for(project).errors << 'leaked'

      expect(described_class.for(project).errors).to be_empty
    end

    it 'returns nil when the saved value has no status' do
      Rails.cache.write(described_class.cache_key(project), { 'bogus' => 1 })

      expect(described_class.for(project)).to be_nil
    end

    it 'returns nil when the saved status is not one it knows' do
      Rails.cache.write(described_class.cache_key(project), { 'status' => 'done' })

      expect(described_class.for(project)).to be_nil
    end
  end

  describe '#save' do
    it 'returns the result' do
      expect(result.save(project)).to be(result)
    end

    it 'expires' do
      expect(Rails.cache).to receive(:write)
        .with(described_class.cache_key(project), result.to_h, expires_in: described_class::CACHE_TTL)

      result.save(project) # rubocop:disable Rails/SaveBang -- not an ActiveRecord save
    end
  end

  describe '#to_h' do
    it 'leaves the time empty when there is none' do
      expect(described_class.new(status: 'failed', commit_sha: nil, synced_at: nil).to_h).to include('synced_at' => nil)
    end

    it 'serialises the time as ISO 8601' do
      expect(result.to_h).to eq(
        'status' => 'partial',
        'commit_sha' => 'abc123',
        'synced_at' => '2026-11-02T10:00:00Z',
        'errors' => [{ 'path' => nil, 'code' => 'failed', 'message' => 'no' }],
        'summary' => { 'created' => %w[build] }
      )
    end
  end
end
