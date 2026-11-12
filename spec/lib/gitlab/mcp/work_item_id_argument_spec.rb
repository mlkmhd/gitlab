# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Mcp::WorkItemIdArgument, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :private, developers: [user]) }
  let_it_be(:project) { create(:project, :private, group: group) }
  let_it_be(:other_project) { create(:project, :private, group: group) }
  let_it_be(:work_item) { create(:work_item, :issue, project: project) }
  let_it_be(:hidden_work_item) { create(:work_item, :issue, project: create(:project, :private)) }

  let(:read_only) { true }
  let(:properties) do
    { url: { type: 'string' }, project_id: { type: 'string' }, group_id: { type: 'string' },
      work_item_iid: { type: 'integer' } }
  end

  let(:tool) do
    instance_double(Mcp::Tools::Base::BaseService,
      annotations: { readOnlyHint: read_only }, input_schema: { type: 'object', properties: properties })
  end

  def normalize(arguments)
    described_class.normalize!(tool, arguments, user)
  end

  describe '.normalize!' do
    context 'with a global ID and a container key' do
      it 'rewrites a WorkItem global ID and keeps the project path' do
        arguments = { 'id' => work_item.to_gid.to_s, 'project_id' => project.full_path }

        expect(normalize(arguments)).to eq(['id:gid->work_item_iid'])
        expect(arguments).to eq('work_item_iid' => work_item.iid, 'project_id' => project.full_path)
      end

      it 'rewrites an Issue global ID and keeps the numeric project ID' do
        arguments = { 'id' => "gid://gitlab/Issue/#{work_item.id}", 'project_id' => project.id.to_s }

        expect(normalize(arguments)).to eq(['id:gid->work_item_iid'])
        expect(arguments).to eq('work_item_iid' => work_item.iid, 'project_id' => project.id.to_s)
      end

      it 'renames a project key that names the work item project' do
        arguments = { 'id' => work_item.to_gid.to_s, 'project' => project.full_path }

        expect(normalize(arguments)).to match_array(['id:gid->work_item_iid', 'project->project_id'])
        expect(arguments).to eq('work_item_iid' => work_item.iid, 'project_id' => project.full_path)
      end

      it 'does not rewrite when the container is another project' do
        arguments = { 'id' => work_item.to_gid.to_s, 'project_id' => other_project.full_path }

        expect(normalize(arguments)).to eq([])
        expect(arguments).to eq('id' => work_item.to_gid.to_s, 'project_id' => other_project.full_path)
      end

      it 'does not rewrite when the container is the work item group' do
        arguments = { 'id' => work_item.to_gid.to_s, 'group_id' => group.full_path }

        expect(normalize(arguments)).to eq([])
      end

      it 'does not rewrite a work item the user cannot read' do
        hidden_path = hidden_work_item.project.full_path
        arguments = { 'id' => hidden_work_item.to_gid.to_s, 'project_id' => hidden_path }

        expect(normalize(arguments)).to eq([])
        expect(arguments).to eq('id' => hidden_work_item.to_gid.to_s, 'project_id' => hidden_path)
      end

      it 'does not rewrite an unknown work item' do
        arguments = { 'id' => "gid://gitlab/WorkItem/#{non_existing_record_id}", 'project_id' => project.full_path }

        expect(normalize(arguments)).to eq([])
      end

      it 'does not rewrite a global ID of another type' do
        arguments = { 'id' => "gid://gitlab/MergeRequest/#{work_item.id}", 'project_id' => project.full_path }

        expect(normalize(arguments)).to eq([])
      end
    end

    context 'with a global ID and no container key' do
      it 'adds the work item project' do
        arguments = { 'id' => work_item.to_gid.to_s }

        expect(normalize(arguments)).to match_array(['id:gid->work_item_iid', 'id:gid->project_id'])
        expect(arguments).to eq('work_item_iid' => work_item.iid, 'project_id' => project.id.to_s)
      end

      it 'does not rewrite a work item the user cannot read' do
        arguments = { 'id' => hidden_work_item.to_gid.to_s }

        expect(normalize(arguments)).to eq([])
        expect(arguments).to eq('id' => hidden_work_item.to_gid.to_s)
      end
    end

    context 'with an iid and a container key' do
      it 'renames project to project_id' do
        arguments = { 'id' => work_item.iid.to_s, 'project' => project.full_path }

        expect(normalize(arguments)).to match_array(['id->work_item_iid', 'project->project_id'])
        expect(arguments).to eq('work_item_iid' => work_item.iid, 'project_id' => project.full_path)
      end

      it 'maps a project path to project_id' do
        arguments = { 'id' => work_item.iid, 'full_path' => project.full_path }

        expect(normalize(arguments)).to match_array(['id->work_item_iid', 'full_path->project_id'])
        expect(arguments).to eq('work_item_iid' => work_item.iid, 'project_id' => project.full_path)
      end

      it 'maps a group path to group_id' do
        arguments = { 'id' => '7', 'namespace_path' => group.full_path }

        expect(normalize(arguments)).to match_array(['id->work_item_iid', 'namespace_path->group_id'])
        expect(arguments).to eq('work_item_iid' => 7, 'group_id' => group.full_path)
      end

      it 'maps a group path the user cannot read to project_id, like a missing path' do
        hidden_path = create(:group, :private).full_path
        arguments = { 'id' => '7', 'full_path' => hidden_path }

        expect(normalize(arguments)).to match_array(['id->work_item_iid', 'full_path->project_id'])
        expect(arguments).to eq('work_item_iid' => 7, 'project_id' => hidden_path)
      end

      it 'maps an unknown path to project_id' do
        arguments = { 'id' => '7', 'namespace' => 'does/not-exist' }

        expect(normalize(arguments)).to match_array(['id->work_item_iid', 'namespace->project_id'])
        expect(arguments).to eq('work_item_iid' => 7, 'project_id' => 'does/not-exist')
      end

      it 'does not rewrite an id sent with project_id, which can be a database ID' do
        arguments = { 'id' => '7', 'project_id' => project.full_path }

        expect(normalize(arguments)).to eq([])
        expect(arguments).to eq('id' => '7', 'project_id' => project.full_path)
      end

      it 'does not rewrite an id sent with group_id, which can be a database ID' do
        arguments = { 'id' => 7, 'group_id' => group.full_path }

        expect(normalize(arguments)).to eq([])
      end

      it 'does not rewrite with two container keys' do
        arguments = { 'id' => '7', 'project' => project.full_path, 'group_id' => group.full_path }

        expect(normalize(arguments)).to eq([])
      end

      it 'does not rewrite a non-numeric id' do
        arguments = { 'id' => 'AI-71', 'project' => project.full_path }

        expect(normalize(arguments)).to eq([])
        expect(arguments).to eq('id' => 'AI-71', 'project' => project.full_path)
      end

      it 'does not rewrite a zero id' do
        arguments = { 'id' => 0, 'project' => project.full_path }

        expect(normalize(arguments)).to eq([])
      end
    end

    it 'does not rewrite an iid without a container key' do
      arguments = { 'id' => '7' }

      expect(normalize(arguments)).to eq([])
      expect(arguments).to eq('id' => '7')
    end

    it 'does not rewrite when the caller sent url' do
      arguments = { 'id' => work_item.to_gid.to_s, 'project_id' => project.full_path, 'url' => 'https://example.com' }

      expect(normalize(arguments)).to eq([])
    end

    it 'does not rewrite when the caller sent an iid' do
      arguments = { 'id' => project.full_path, 'work_item_iid' => 1 }

      expect(normalize(arguments)).to eq([])
      expect(arguments).to eq('id' => project.full_path, 'work_item_iid' => 1)
    end

    context 'when the tool is not read-only' do
      let(:read_only) { false }

      it 'does not rewrite' do
        arguments = { 'id' => '7', 'project_id' => project.full_path }

        expect(normalize(arguments)).to eq([])
      end
    end

    context 'when the schema does not declare work_item_iid' do
      let(:properties) { { project_id: { type: 'string' } } }

      it 'does not rewrite' do
        arguments = { 'id' => '7', 'project_id' => project.full_path }

        expect(normalize(arguments)).to eq([])
      end
    end

    context 'when the schema declares id' do
      let(:properties) do
        { id: { type: 'string' }, project_id: { type: 'string' }, work_item_iid: { type: 'integer' } }
      end

      it 'does not rewrite' do
        arguments = { 'id' => '7', 'project_id' => project.full_path }

        expect(normalize(arguments)).to eq([])
      end
    end
  end

  it 'applies to the read-only tools that declare work_item_iid' do
    names = Mcp::Tools::Manager.new.tools.select do |_name, registered|
      registered.annotations[:readOnlyHint] &&
        registered.input_schema.to_h.with_indifferent_access[:properties]&.key?(:work_item_iid)
    end.keys

    expect(names).to contain_exactly('get_work_item', 'get_workitem_notes')
  end
end
