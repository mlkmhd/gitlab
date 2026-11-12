# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Mcp::WorkItemIdArgument, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :private, developers: [user]) }
  let_it_be(:epic) { create(:epic, group: group) }

  let(:properties) { { group_id: { type: 'string' }, work_item_iid: { type: 'integer' } } }
  let(:tool) do
    instance_double(Mcp::Tools::Base::BaseService,
      annotations: { readOnlyHint: true }, input_schema: { type: 'object', properties: properties })
  end

  before do
    stub_licensed_features(epics: true)
  end

  describe '.normalize!' do
    it 'rewrites an Epic global ID and keeps the group' do
      arguments = { 'id' => epic.to_gid.to_s, 'group_id' => group.full_path }

      expect(described_class.normalize!(tool, arguments, user)).to eq(['id:gid->work_item_iid'])
      expect(arguments).to eq('work_item_iid' => epic.work_item.iid, 'group_id' => group.full_path)
    end

    it 'rewrites a group-level WorkItem global ID sent with the group path' do
      arguments = { 'id' => epic.work_item.to_gid.to_s, 'full_path' => group.full_path }

      expect(described_class.normalize!(tool, arguments, user))
        .to match_array(['id:gid->work_item_iid', 'full_path->group_id'])
      expect(arguments).to eq('work_item_iid' => epic.work_item.iid, 'group_id' => group.full_path)
    end

    it 'adds the group to an Epic global ID sent without a container' do
      arguments = { 'id' => epic.to_gid.to_s }

      expect(described_class.normalize!(tool, arguments, user))
        .to match_array(['id:gid->work_item_iid', 'id:gid->group_id'])
      expect(arguments).to eq('work_item_iid' => epic.work_item.iid, 'group_id' => group.id.to_s)
    end

    it 'does not rewrite an epic sent with another group' do
      arguments = { 'id' => epic.to_gid.to_s, 'group_id' => create(:group, developers: [user]).full_path }

      expect(described_class.normalize!(tool, arguments, user)).to eq([])
    end

    it 'does not rewrite an epic the user cannot read' do
      arguments = { 'id' => epic.to_gid.to_s, 'group_id' => group.full_path }

      expect(described_class.normalize!(tool, arguments, create(:user))).to eq([])
      expect(arguments).to eq('id' => epic.to_gid.to_s, 'group_id' => group.full_path)
    end

    it 'does not rewrite an unknown epic' do
      arguments = { 'id' => "gid://gitlab/Epic/#{non_existing_record_id}", 'group_id' => group.full_path }

      expect(described_class.normalize!(tool, arguments, user)).to eq([])
    end
  end
end
