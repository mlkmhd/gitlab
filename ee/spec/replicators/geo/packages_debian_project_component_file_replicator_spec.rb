# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::PackagesDebianProjectComponentFileReplicator, feature_category: :geo_replication do
  let(:model_record) { create(:debian_project_component_file) }

  include_examples 'a blob replicator'

  it_behaves_like 'a blob replicator that loads blob location records in bulk' do
    let_it_be(:other_records) { create_list(:debian_project_component_file, 2) }
  end
end
