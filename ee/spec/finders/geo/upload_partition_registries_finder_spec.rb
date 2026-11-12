# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::UploadPartitionRegistriesFinder, :enable_admin_mode, feature_category: :geo_replication do
  include ::EE::GeoHelpers

  let_it_be(:admin) { create(:user, :admin) }

  let_it_be(:project_registry1) { create(:geo_project_upload_registry, :synced) }
  let_it_be(:project_registry2) { create(:geo_project_upload_registry, :failed) }
  let_it_be(:group_registry) { create(:geo_group_upload_registry, :synced) }
  let_it_be(:legacy_registry) { create(:geo_upload_registry, :synced) }

  let(:params) { {} }
  let(:user) { admin }

  subject(:registries) { described_class.new(user, params).execute }

  before do
    stub_current_geo_node(create(:geo_node))
  end

  def upload_id(registry)
    registry.public_send(registry.class.model_foreign_key)
  end

  it 'returns read-only rows, since their ids are upload ids' do
    expect(registries).to all(be_readonly)
  end

  context 'when the user cannot read all Geo' do
    let(:user) { create(:user) }

    it { is_expected.to be_empty }
  end

  context 'when no partition replication is enabled' do
    before do
      Gitlab::Geo.upload_partition_replicator_classes.each do |replicator|
        stub_feature_flags(replicator.replication_enabled_feature_key => false)
      end
    end

    it { is_expected.to be_empty }
  end

  context 'when a partition replication flag is disabled' do
    before do
      stub_feature_flags(geo_group_upload_replication: false)
    end

    it 'excludes that partition' do
      expect(registries.map(&:id)).to match_array([project_registry1, project_registry2].map { |r| upload_id(r) })
    end
  end

  context 'with a keyword param' do
    let(:params) { { keyword: 'abc' } }

    it 'searches the uploads by checksum' do
      matching = Upload.find(upload_id(project_registry1))
      matching.update!(checksum: 'abc')

      expect(registries.map(&:id)).to contain_exactly(matching.id)
    end
  end

  context 'with a verification_state param when verification is disabled for a partition' do
    let(:params) { { verification_state: :succeeded } }

    before do
      allow(Geo::ProjectUploadReplicator).to receive(:verification_enabled?).and_return(false)
    end

    it 'raises an error' do
      expect { registries }.to raise_error(ArgumentError, /verification_state is not supported/)
    end
  end

  context 'with a verified_at sort when verification is disabled for a partition' do
    let(:params) { { sort: :verified_at_desc } }

    before do
      allow(Geo::ProjectUploadReplicator).to receive(:verification_enabled?).and_return(false)
    end

    it 'raises an error' do
      expect { registries }.to raise_error(ArgumentError, /Sorting by verified_at is not supported/)
    end
  end
end
