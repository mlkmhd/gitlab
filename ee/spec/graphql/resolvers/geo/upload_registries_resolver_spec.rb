# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Geo::UploadRegistriesResolver, feature_category: :geo_replication do
  include GraphqlHelpers
  include EE::GeoHelpers

  it_behaves_like 'a Geo registries resolver', :geo_upload_registry

  context 'with partition registries', :enable_admin_mode do
    let_it_be(:secondary, freeze: true) { create(:geo_node) }
    let_it_be(:current_user, freeze: true) { create(:admin) }

    let_it_be(:partition_registry) { create(:geo_project_upload_registry) }
    let_it_be(:legacy_registry) { create(:geo_upload_registry) }

    before do
      stub_current_geo_node(secondary)
    end

    subject(:result) { resolve(described_class, obj: secondary, args: {}, ctx: { current_user: current_user }) }

    context 'when geo_upload_replication is disabled' do
      before do
        stub_feature_flags(geo_upload_replication: false)
      end

      it 'returns the partition registries keyed by upload id' do
        expect(result.map(&:id)).to eq([partition_registry.project_upload_id])
      end
    end

    context 'when geo_upload_replication is enabled' do
      it 'ignores the partition registries' do
        expect(result.to_a).to eq([legacy_registry])
      end
    end
  end
end
