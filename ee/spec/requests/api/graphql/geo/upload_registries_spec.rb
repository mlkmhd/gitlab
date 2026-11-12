# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Gets upload registries when geo_upload_replication is disabled', feature_category: :geo_replication do
  include GraphqlHelpers
  include EE::GeoHelpers

  let_it_be(:current_user) { create(:user, :admin) }
  let_it_be(:secondary) { create(:geo_node) }
  let_it_be(:project_registry) { create(:geo_project_upload_registry, :synced) }
  let_it_be(:user_registry) { create(:geo_user_upload_registry, :failed) }
  let_it_be(:project_registry2) { create(:geo_project_upload_registry) }
  let_it_be(:legacy_registry) { create(:geo_upload_registry) }

  let(:data_path) { [:geo_node, :upload_registries] }

  before do
    stub_current_geo_node(secondary)
    stub_current_node_name(secondary.name)
    stub_feature_flags(geo_upload_replication: false)
  end

  def pagination_query(arguments)
    graphql_query_for(:geo_node, {},
      query_nodes(:upload_registries, :file_id, include_pagination_info: true, args: arguments))
  end

  def pagination_results_data(nodes)
    nodes.map { |node| node['fileId'].to_i }
  end

  it 'returns the partition registries keyed by upload ID' do
    post_graphql(
      '{ geoNode { uploadRegistries { nodes { id fileId modelRecordId state missingOnPrimary ' \
        'dataManagementDetailsPath } } } }',
      current_user: current_user
    )

    expect(graphql_data_at(*data_path, :nodes)).to match_array(
      [
        [project_registry, 'geo_project_uploads'],
        [project_registry2, 'geo_project_uploads'],
        [user_registry, 'geo_user_uploads']
      ].map do |registry, plural|
        upload_id = registry.model_record_id
        {
          'id' => Geo::UploadRegistry.new(id: upload_id).to_global_id.to_s,
          'fileId' => upload_id.to_s,
          'modelRecordId' => upload_id,
          'state' => registry.state_name.to_s.upcase,
          'missingOnPrimary' => false,
          'dataManagementDetailsPath' => "/admin/data_management/#{plural}/#{upload_id}"
        }
      end
    )
  end

  it 'filters by replication state' do
    post_graphql(
      '{ geoNode { uploadRegistries(replicationState: FAILED) { nodes { fileId } } } }',
      current_user: current_user
    )

    expect(graphql_data_at(*data_path, :nodes)).to contain_exactly('fileId' => user_registry.model_record_id.to_s)
  end

  context 'when paginating' do
    let(:ordered_ids) { [project_registry, user_registry, project_registry2].map(&:model_record_id).sort }

    it_behaves_like 'sorted paginated query' do
      let(:sort_param) { :ID_ASC }
      let(:first_param) { 2 }
      let(:all_records) { ordered_ids }
    end

    it_behaves_like 'sorted paginated query' do
      let(:sort_param) { :ID_DESC }
      let(:first_param) { 2 }
      let(:all_records) { ordered_ids.reverse }
    end
  end

  context 'when paginating with ties and NULLs' do
    let_it_be(:group_registry) { create(:geo_group_upload_registry) }
    let_it_be(:group_registry2) { create(:geo_group_upload_registry) }

    let(:tied_at) { 2.days.ago.change(usec: 0) }

    def set_timestamps(column, timestamps)
      timestamps.each do |registry, value|
        registry.class.where(id: registry.id).update_all(column => value)
      end
    end

    # The finder orders `column ASC` and keyset pagination appends `id DESC` as tie-breaker, with NULLs last
    # for ASC. The `id` is the upload ID.
    context 'when sorting by verified_at ascending' do
      let(:ordered_records) do
        tied = [project_registry, user_registry].sort_by(&:model_record_id).reverse
        nulls = [project_registry2, group_registry2].sort_by(&:model_record_id).reverse

        [*tied, group_registry, *nulls].map(&:model_record_id)
      end

      before do
        set_timestamps(:verified_at, {
          project_registry => tied_at,
          user_registry => tied_at,
          group_registry => 1.day.ago,
          project_registry2 => nil,
          group_registry2 => nil
        })
      end

      [1, 2, 3, 4].each do |page_size|
        context "with first: #{page_size}" do
          it_behaves_like 'sorted paginated query' do
            let(:sort_param) { :VERIFIED_AT_ASC }
            let(:first_param) { page_size }
            let(:all_records) { ordered_records }
          end
        end
      end
    end

    # With `last_synced_at DESC`, NULLs come first and the tie-breaker is still `id DESC`.
    context 'when sorting by last_synced_at descending' do
      let(:ordered_records) do
        nulls = [project_registry2, group_registry2].sort_by(&:model_record_id).reverse
        tied = [user_registry, group_registry].sort_by(&:model_record_id).reverse

        [*nulls, *tied, project_registry].map(&:model_record_id)
      end

      before do
        set_timestamps(:last_synced_at, {
          project_registry => 5.days.ago,
          user_registry => tied_at,
          group_registry => tied_at,
          project_registry2 => nil,
          group_registry2 => nil
        })
      end

      [1, 2, 3, 4].each do |page_size|
        context "with first: #{page_size}" do
          it_behaves_like 'sorted paginated query' do
            let(:sort_param) { :LAST_SYNCED_AT_DESC }
            let(:first_param) { page_size }
            let(:all_records) { ordered_records }
          end
        end
      end
    end
  end

  describe 'filtering by IDs and verification state' do
    let_it_be(:verified_registry) { create(:geo_group_upload_registry, :verification_succeeded) }

    it 'round-trips a returned ID through the ids argument' do
      post_graphql('{ geoNode { uploadRegistries { nodes { id fileId } } } }', current_user: current_user)

      node = graphql_data_at(*data_path, :nodes).first
      expect(node['id']).to eq(Geo::UploadRegistry.new(id: node['fileId']).to_global_id.to_s)

      post_graphql(
        "{ geoNode { uploadRegistries(ids: [\"#{node['id']}\"]) { nodes { id fileId } } } }",
        current_user: current_user
      )

      expect(graphql_data_at(*data_path, :nodes)).to contain_exactly(node)
    end

    it 'filters by verification state' do
      post_graphql(
        '{ geoNode { uploadRegistries(verificationState: SUCCEEDED) { nodes { fileId verificationState } } } }',
        current_user: current_user
      )

      expect(graphql_data_at(*data_path, :nodes)).to contain_exactly(
        'fileId' => verified_registry.model_record_id.to_s, 'verificationState' => 'SUCCEEDED'
      )
    end
  end

  describe 'count' do
    def count_query(arguments = '')
      "{ geoNode { uploadRegistries#{arguments} { count } } }"
    end

    it 'counts the partition registries and excludes legacy registries' do
      post_graphql(count_query, current_user: current_user)

      expect(graphql_data_at(*data_path, :count)).to eq(3)
    end

    it 'counts the filtered registries' do
      post_graphql(count_query('(replicationState: FAILED)'), current_user: current_user)

      expect(graphql_data_at(*data_path, :count)).to eq(1)
    end
  end

  describe 'field parity with the partition registry' do
    let_it_be(:full_registry) do
      create(:geo_group_upload_registry,
        state: Geo::GroupUploadRegistry.state_value(:failed),
        last_sync_failure: 'Sync failed',
        last_synced_at: 3.days.ago,
        retry_count: 4,
        retry_at: 1.hour.from_now,
        verification_state: Geo::GroupUploadRegistry.verification_state_value(:verification_failed),
        verification_failure: 'Checksum failed',
        verification_retry_count: 3,
        verification_retry_at: 2.hours.from_now,
        verification_started_at: 4.hours.ago,
        verified_at: 6.days.ago,
        verification_checksum: 'e079a831cab27bcda7d81cd9b48296d0c3dd92ef',
        verification_checksum_mismatched: '0123456789abcdef0123456789abcdef01234567',
        checksum_mismatch: true)
    end

    let(:non_deprecated_fields) do
      Types::Geo::UploadRegistryType.fields.values.reject(&:deprecation).map(&:graphql_name)
    end

    it 'returns the same values as the partition registry' do
      global_id = Geo::UploadRegistry.new(id: full_registry.model_record_id).to_global_id

      post_graphql(
        "{ geoNode { uploadRegistries(ids: [\"#{global_id}\"]) " \
          "{ nodes { #{non_deprecated_fields.join(' ')} } } } }",
        current_user: current_user
      )

      source = Geo::GroupUploadRegistry.find(full_registry.id)
      upload_id = source.model_record_id

      expect(graphql_data_at(*data_path, :nodes)).to contain_exactly(
        'id' => Geo::UploadRegistry.new(id: upload_id).to_global_id.to_s,
        'fileId' => upload_id.to_s,
        'modelRecordId' => upload_id,
        'state' => 'FAILED',
        'lastSyncFailure' => 'Sync failed',
        'lastSyncedAt' => source.last_synced_at.iso8601,
        'retryCount' => 4,
        'retryAt' => source.retry_at.iso8601,
        'createdAt' => source.created_at.iso8601,
        'missingOnPrimary' => false,
        'checksumMismatch' => true,
        'verificationState' => 'FAILED',
        'verificationFailure' => 'Checksum failed',
        'verificationRetryCount' => 3,
        'verificationRetryAt' => source.verification_retry_at.iso8601,
        'verificationStartedAt' => source.verification_started_at.iso8601,
        'verifiedAt' => source.verified_at.iso8601,
        'verificationChecksum' => source.verification_checksum,
        'verificationChecksumMismatched' => source.verification_checksum_mismatched,
        'dataManagementDetailsPath' => "/admin/data_management/geo_group_uploads/#{upload_id}"
      )
    end
  end

  describe 'access boundaries' do
    let_it_be(:primary) { create(:geo_node, :primary) }

    it 'returns no registries for a Geo node that is not the current node' do
      post_graphql(
        "{ geoNode(name: \"#{primary.name}\") { uploadRegistries { nodes { fileId } } } }",
        current_user: current_user
      )

      expect(graphql_data_at(:geo_node, :upload_registries, :nodes)).to be_empty
    end

    it 'does not return the Geo node to a non-admin user' do
      post_graphql(
        '{ geoNode { uploadRegistries { nodes { fileId } } } }',
        current_user: create(:user)
      )

      expect(graphql_data_at(:geo_node)).to be_nil
    end
  end
end
