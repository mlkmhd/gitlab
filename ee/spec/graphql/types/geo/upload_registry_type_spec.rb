# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['UploadRegistry'], feature_category: :geo_replication do
  include GraphqlHelpers
  include ::EE::GeoHelpers

  it_behaves_like 'a Geo registry type'

  it 'has the expected fields (other than those included in RegistryType)' do
    expected_fields = %i[file_id]

    expect(described_class).to have_graphql_fields(*expected_fields).at_least
  end

  describe '#data_management_details_path', :enable_admin_mode do
    let_it_be(:admin) { create(:user, :admin) }

    context 'with a legacy registry' do
      let(:registry) { create(:geo_upload_registry) }

      it 'builds the path from the legacy replicator' do
        expect(resolve_field(:data_management_details_path, registry, current_user: admin))
          .to eq("/admin/data_management/uploads/#{registry.file_id}")
      end
    end

    context 'with a partition registry row' do
      let_it_be(:partition_registry) { create(:geo_project_upload_registry) }

      before do
        stub_current_geo_node(create(:geo_node))
        stub_feature_flags(geo_upload_replication: false)
      end

      it 'builds the path from the partition replicator' do
        row = Geo::UploadPartitionRegistriesFinder.new(admin, {}).execute.first

        expect(resolve_field(:data_management_details_path, row, current_user: admin))
          .to eq("/admin/data_management/geo_project_uploads/#{partition_registry.model_record_id}")
      end
    end

    context 'without a model record ID' do
      let(:registry) { build(:geo_upload_registry, file_id: nil) }

      it 'returns nil' do
        expect(resolve_field(:data_management_details_path, registry, current_user: admin)).to be_nil
      end
    end
  end
end
