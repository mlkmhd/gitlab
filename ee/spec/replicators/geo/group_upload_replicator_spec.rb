# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::GroupUploadReplicator, feature_category: :geo_replication do
  let(:model_record) { create(:geo_group_upload) }

  include_examples 'a blob replicator with a read-only replicable model'
  include_examples 'a blob replicator with upload replicator behavior'

  it_behaves_like 'a blob replicator that loads blob location records in bulk' do
    let_it_be(:other_records) { create_list(:geo_group_upload, 2) }
  end
end
