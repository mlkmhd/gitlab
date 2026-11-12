# frozen_string_literal: true

# Include in a blob replicator spec to check that blob_location_records does not issue per-record queries.
#
# Required let variables: model_record, other_records.
RSpec.shared_examples 'a blob replicator that loads blob location records in bulk' do
  describe '.blob_location_records' do
    it 'computes the blob location of more records with the same number of queries' do
      records = [model_record] + other_records
      compute = ->(ids) do
        described_class.blob_location_records(ids).map do |record|
          described_class.new(model_record: record).registry_blob_location
        end
      end

      compute.call([model_record.id])
      control = ActiveRecord::QueryRecorder.new { compute.call([model_record.id]) }

      expect { compute.call(records.map(&:id)) }.not_to exceed_query_limit(control)

      locations = compute.call(records.map(&:id))
      expect(locations.size).to eq(records.size)
      expect(locations).to all(include(blob_path: be_present))
    end
  end
end
