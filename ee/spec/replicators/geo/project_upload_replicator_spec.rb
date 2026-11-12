# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::ProjectUploadReplicator, feature_category: :geo_replication do
  let(:model_record) { create(:geo_project_upload) }

  include_examples 'a blob replicator with a read-only replicable model'
  include_examples 'a blob replicator with upload replicator behavior'

  it_behaves_like 'a blob replicator that loads blob location records in bulk' do
    let_it_be(:other_records) { create_list(:geo_project_upload, 2) }
  end
end
