# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Database::SearchPathInformation, feature_category: :database do
  describe '.execute' do
    subject(:result) { described_class.execute }

    it 'returns the search path check for the main database by default', :aggregate_failures do
      expect(result[:databases].keys).to eq(%w[main])

      payload = result[:databases]['main']
      expect(payload[:current_user]).to be_a(String).and(be_present)
      expect(payload[:search_path]).to be_a(String).and(be_present)
      expect(payload[:schemas]).to be_an(Array).and(be_present)
      expect(payload).to include(:severity, :counts)
      expect(payload[:findings]).to be_an(Array)
    end

    it 'returns the check result as the payload' do
      check_result = { search_path: 'public', findings: [], severity: nil, counts: {} }

      expect_next_instance_of(Gitlab::Database::Diagnostics::Checks::SchemaResolution) do |check|
        expect(check).to receive(:execute).and_return(check_result)
      end

      expect(result[:databases]['main']).to eq(check_result)
    end

    context 'when a database name does not map to a known model' do
      subject(:result) { described_class.execute(database_names: %w[bogus]) }

      it 'returns an error payload for that database' do
        expect(result[:databases]['bogus']).to eq(error: 'Unknown database: bogus')
      end
    end

    context 'when the connection raises an error' do
      let(:failing_model) { class_double(ApplicationRecord) }
      let(:error) { StandardError.new('PG::ConnectionBad: could not connect to host db.internal:5432') }

      before do
        allow(Gitlab::Database).to receive(:database_base_models)
          .and_return({ 'main' => failing_model })
        allow(failing_model).to receive(:connection).and_raise(error)
      end

      it 'returns a sanitized error payload and tracks the exception', :aggregate_failures do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error, database_name: 'main')

        expect(result[:databases]['main']).to eq(error: 'Failed to gather information for database: main')
      end
    end
  end
end
