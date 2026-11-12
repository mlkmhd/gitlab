# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::DapFactory::SyncResultType, feature_category: :dap_triggers do
  include GraphqlHelpers

  specify { expect(described_class.graphql_name).to eq('DapFactorySyncResult') }

  it 'has the expected fields' do
    expect(described_class).to have_graphql_fields(
      :status, :commit_sha, :synced_at, :errors,
      :adopted_stages, :created_stages, :updated_stages, :deleted_stages, :failed_stages
    )
  end

  describe '#errors' do
    it 'turns the saved hashes into messages' do
      result = ::Ai::DapFactory::SyncResult.new(status: 'failed', commit_sha: nil, synced_at: nil,
        errors: [{ 'path' => nil, 'code' => 'failed', 'message' => 'no' }])

      expect(resolve_field(:errors, result)).to contain_exactly(
        have_attributes(path: nil, code: 'failed', message: 'no')
      )
    end
  end

  describe 'stage fields' do
    let(:stage_fields) { %i[adopted_stages created_stages updated_stages deleted_stages failed_stages] }

    it 'reads each list from the summary' do
      result = ::Ai::DapFactory::SyncResult.new(
        status: 'partial', commit_sha: 'abc123', synced_at: Time.current,
        summary: {
          'adopted' => %w[triage], 'created' => %w[plan], 'updated' => %w[build], 'deleted' => %w[verify],
          'failed' => [{ 'stage' => 'review', 'message' => 'boom' }]
        }
      )

      expect(stage_fields.map { |field| resolve_field(field, result) }).to match([
        %w[triage], %w[plan], %w[build], %w[verify],
        [have_attributes(path: 'stages.review', code: 'sync_failed', message: 'boom')]
      ])
    end

    it 'is empty when the summary has no stages' do
      result = ::Ai::DapFactory::SyncResult.new(status: 'failed', commit_sha: nil, synced_at: nil)

      expect(stage_fields.map { |field| resolve_field(field, result) }).to all(be_empty)
    end
  end
end
