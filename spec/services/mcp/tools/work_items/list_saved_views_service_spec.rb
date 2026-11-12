# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::WorkItems::ListSavedViewsService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:other_user) { create(:user) }
  let_it_be(:group) { create(:group, :private, developers: [user, other_user]) }
  let_it_be(:project) { create(:project, :private, group: group) }

  let_it_be(:bugs_view) { create(:saved_view, namespace: group, author: user, name: 'Bugs', description: 'Open bugs') }
  let_it_be(:roadmap_view) do
    create(:saved_view, namespace: group, author: user, name: 'Roadmap', description: 'Planned work')
  end

  let_it_be(:private_view_of_other_user) do
    create(:saved_view, namespace: group, author: other_user, name: 'Mine only', private: true)
  end

  let_it_be(:project_view) { create(:saved_view, namespace: project.project_namespace, author: user, name: 'Project') }

  let(:service) { described_class.new(name: 'list_work_item_saved_views') }
  let(:arguments) { { group_id: group.full_path } }

  subject(:result) { service.execute(params: { arguments: arguments }) }

  before do
    service.set_cred(current_user: user)
  end

  def saved_view_names
    result[:structuredContent]['saved_views'].pluck('name')
  end

  describe 'class configuration', :aggregate_failures do
    it 'registers version 0.1.0 as a read-only work_items tool' do
      expect(described_class.available_versions).to include('0.1.0')
      expect(service.toolset).to eq(:work_items)
      expect(service.annotations).to eq(
        title: 'List work item saved views', readOnlyHint: true, idempotentHint: true, openWorldHint: false
      )
    end

    it 'offers only the saved view sort values' do
      expect(service.input_schema[:properties][:sort][:enum]).to eq(%w[ID NAME_ASC RELATIVE_POSITION])
    end
  end

  describe '#perform_default' do
    it 'delegates to perform_v0_1_0' do
      expect(service).to receive(:perform_v0_1_0).with(arguments)

      service.send(:perform_default, arguments)
    end
  end

  describe '#execute', :aggregate_failures do
    it 'lists the saved views the user can see in the group' do
      expect(result[:isError]).to be(false)
      expect(saved_view_names).to contain_exactly('Bugs', 'Roadmap')
    end

    context 'with project_id' do
      let(:arguments) { { project_id: project.full_path } }

      it 'lists the saved views of the project' do
        expect(saved_view_names).to contain_exactly('Project')
      end
    end

    context 'with url' do
      let(:arguments) { { url: Gitlab::Routing.url_helpers.group_url(group) } }

      it 'lists the saved views of the namespace in the URL' do
        expect(saved_view_names).to contain_exactly('Bugs', 'Roadmap')
      end
    end

    context 'with search' do
      let(:arguments) { { group_id: group.full_path, search: 'planned' } }

      it 'returns the matching saved views' do
        expect(saved_view_names).to contain_exactly('Roadmap')
      end
    end

    context 'with subscribed_only' do
      let(:arguments) { { group_id: group.full_path, subscribed_only: true } }

      before do
        create(:user_saved_view, user: user, saved_view: roadmap_view, namespace: group)
      end

      it 'returns only the subscribed saved views' do
        expect(saved_view_names).to contain_exactly('Roadmap')
      end
    end

    context 'with sort and pagination' do
      let(:arguments) { { group_id: group.full_path, sort: 'NAME_ASC', first: 1 } }

      it 'returns the first page and a cursor for the next one' do
        expect(saved_view_names).to eq(['Bugs'])
        expect(result[:structuredContent]['pageInfo']).to include('hasNextPage' => true, 'endCursor' => be_present)
      end
    end

    context 'with an unsupported sort value' do
      let(:arguments) { { group_id: group.full_path, sort: 'CREATED_DESC' } }

      it 'returns a validation error' do
        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to start_with("Validation error: Invalid sort: 'CREATED_DESC'")
      end
    end

    context 'with RELATIVE_POSITION sort and no subscribed_only' do
      let(:arguments) { { group_id: group.full_path, sort: 'RELATIVE_POSITION' } }

      it 'returns a validation error' do
        expect(result[:isError]).to be(true)
        expect(result[:reason]).to eq(:bad_request)
        expect(result[:content].first[:text])
          .to eq('Validation error: sort RELATIVE_POSITION requires subscribed_only: true')
      end
    end

    context 'when the user cannot read the group' do
      before do
        service.set_cred(current_user: create(:user))
      end

      it 'returns an access error' do
        expect(result[:isError]).to be(true)
        expect(result[:reason]).to eq(:unauthorized)
        expect(result[:content].first[:text])
          .to eq("Tool execution failed: Group '#{group.full_path}' not found or inaccessible")
      end
    end
  end

  # The tool lists saved views of one namespace only, not its subgroups, so added records
  # stay in that namespace with a new author each.
  describe 'N+1 queries' do
    let_it_be(:n_plus_one_group) { create(:group, :public, developers: user) }
    let_it_be(:n_plus_one_project) { create(:project, :public, group: n_plus_one_group) }

    def create_saved_view(namespace)
      author = create(:user, developer_of: n_plus_one_group)
      view = create(:saved_view, namespace: namespace, author: author)
      create(:user_saved_view, user: user, saved_view: view, namespace: namespace)
    end

    context 'with group_id' do
      it_behaves_like 'an MCP tool that avoids N+1 queries' do
        let(:arguments) { { group_id: n_plus_one_group.full_path } }

        before_all do
          create_saved_view(n_plus_one_group)
        end

        def create_additional_records
          2.times { create_saved_view(n_plus_one_group) }
        end
      end
    end

    context 'with project_id' do
      it_behaves_like 'an MCP tool that avoids N+1 queries' do
        let(:arguments) { { project_id: n_plus_one_project.full_path } }

        before_all do
          create_saved_view(n_plus_one_project.project_namespace)
        end

        def create_additional_records
          2.times { create_saved_view(n_plus_one_project.project_namespace) }
        end
      end
    end
  end
end
