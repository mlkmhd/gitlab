# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::WorkItems::ListSavedViewsTool, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :private, developers: user) }

  let(:params) { { group_id: group.id.to_s } }
  let(:tool) { described_class.new(current_user: user, params: params, access_token: nil) }

  describe 'versioning' do
    it 'registers version 0.1.0 with the listSavedViews query', :aggregate_failures do
      expect(tool.version).to eq(Mcp::Tools::Concerns::Constants::VERSIONS[:v0_1_0])
      expect(tool.operation_name).to eq('namespace')
      expect(tool.graphql_operation).to include('query listSavedViews')
    end
  end

  describe '#build_variables' do
    let(:params) do
      { group_id: group.id.to_s, search: 'bugs', subscribed_only: true, sort: 'NAME_ASC', first: 5, after: 'abc' }
    end

    it 'passes the namespace path, filters, and pagination' do
      expect(tool.build_variables).to eq(
        fullPath: group.full_path, search: 'bugs', subscribedOnly: true, sort: 'NAME_ASC', first: 5, after: 'abc'
      )
    end

    context 'when only the namespace is given' do
      let(:params) { { group_id: group.id.to_s } }

      it 'leaves out the optional variables and uses the default page size' do
        expect(tool.build_variables).to eq(fullPath: group.full_path, first: 20)
      end
    end

    context 'when more than one of url, project_id, and group_id is given' do
      let(:params) { { group_id: group.id.to_s, project_id: '1' } }

      it 'raises an error' do
        expect { tool.build_variables }.to raise_error(
          ArgumentError, 'Provide exactly one of url, project_id, or group_id (got project_id, group_id)'
        )
      end
    end

    context 'when sort is RELATIVE_POSITION without subscribed_only' do
      let(:params) { { group_id: group.id.to_s, sort: 'RELATIVE_POSITION' } }

      it 'raises an error' do
        expect { tool.build_variables }.to raise_error(
          ArgumentError, 'sort RELATIVE_POSITION requires subscribed_only: true'
        )
      end
    end

    context 'when sort is RELATIVE_POSITION with subscribed_only' do
      let(:params) { { group_id: group.id.to_s, sort: 'RELATIVE_POSITION', subscribed_only: true } }

      it 'passes the sort' do
        expect(tool.build_variables).to include(sort: 'RELATIVE_POSITION', subscribedOnly: true)
      end
    end
  end

  describe '#execute', :aggregate_failures do
    let_it_be(:saved_view) { create(:saved_view, namespace: group, name: 'Open bugs') }

    it 'returns the saved views and page info' do
      result = tool.execute

      expect(result[:isError]).to be(false)
      expect(result[:structuredContent]['saved_views']).to contain_exactly(
        a_hash_including('id' => saved_view.id, 'name' => 'Open bugs')
      )
      expect(result[:structuredContent]['saved_views'].first['id']).to be_an(Integer)
      expect(result[:structuredContent]['pageInfo']).to match('endCursor' => be_present, 'hasNextPage' => false)
      expect(Gitlab::Json::SafeParser.parse(result[:content].first[:text])).to eq(result[:structuredContent])
    end

    context 'when the namespace returns no saved views connection' do
      before do
        allow(GitlabSchema).to receive(:execute).and_return(
          { 'data' => { 'namespace' => { 'id' => group.to_global_id.to_s, 'savedViews' => nil } } }
        )
      end

      it 'returns a not found error' do
        result = tool.execute

        expect(result[:isError]).to be(true)
        expect(result[:reason]).to eq(:not_found)
        expect(result[:content].first[:text]).to eq(
          'Project or group not found: it does not exist or you do not have access to it.'
        )
      end
    end

    context 'when GraphQL returns errors' do
      before do
        allow(GitlabSchema).to receive(:execute).and_return({ 'errors' => [{ 'message' => 'Some error' }] })
      end

      it 'returns the error' do
        result = tool.execute

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to eq('Some error')
      end
    end
  end
end
