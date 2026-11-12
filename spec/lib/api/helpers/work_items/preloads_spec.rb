# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Helpers::WorkItems::Preloads, feature_category: :portfolio_management do
  # `freeze: false` is required in this spec: the bare helper instance is a non-AR subject that
  # cannot be deep-frozen. Do not convert it to `let_it_be_with_reload`/`refind`.
  let_it_be(:helper, freeze: false) { Class.new.include(API::Helpers).include(described_class).new }
  let_it_be(:user) { create(:user) }
  let_it_be(:work_item) { create(:work_item) }

  before do
    allow(helper).to receive(:current_user).and_return(user)
  end

  describe '#work_item_for!' do
    before_all do
      work_item.project.add_developer(user)
    end

    it 'scopes the finder to the parent and iid only, ignoring request filter params' do
      allow(helper).to receive(:params)
        .and_return({ state: 'closed', search: 'no-such-title', include_descendants: true })

      expect(::WorkItems::WorkItemsFinder).to receive(:new)
        .with(user, { project_id: work_item.project_id, iids: [work_item.iid] })
        .and_call_original

      expect(helper.work_item_for!(work_item.project, work_item.iid)).to eq(work_item)
    end
  end

  describe '#preload_work_item_policies' do
    it 'preloads the project policies behind the read checks' do
      expect(::Preloaders::UserMaxAccessLevelInProjectsPreloader).to receive(:new).and_call_original

      helper.preload_work_item_policies([work_item])
    end

    it 'does nothing without a current user' do
      allow(helper).to receive(:current_user).and_return(nil)
      expect(::Preloaders::UserMaxAccessLevelInProjectsPreloader).not_to receive(:new)

      helper.preload_work_item_policies([work_item])
    end

    it 'does nothing for a blank collection' do
      expect(::Preloaders::UserMaxAccessLevelInProjectsPreloader).not_to receive(:new)

      helper.preload_work_item_policies([])
    end
  end

  describe '#preload_hierarchy_authorization' do
    # Scoped with `.with` so unrelated framework calls to the same preloader (Banzai reference
    # parsing during factory setup) can't satisfy or break these expectations.
    let_it_be(:parent_project) { work_item.project }
    let_it_be_with_reload(:child) { create(:work_item, :task, project: parent_project) }
    let_it_be(:orphan) { create(:work_item) }

    before_all do
      create(:parent_link, work_item: child, work_item_parent: work_item)
    end

    it 'preloads policies for the hierarchy parents' do
      expect(::Preloaders::UserMaxAccessLevelInProjectsPreloader)
        .to receive(:new).with([parent_project], user).and_call_original

      helper.preload_hierarchy_authorization([child], [:hierarchy])
    end

    it 'does nothing unless the hierarchy feature was requested' do
      expect(::Preloaders::UserMaxAccessLevelInProjectsPreloader)
        .not_to receive(:new).with([parent_project], user)

      helper.preload_hierarchy_authorization([child], [:labels])
    end

    it 'does nothing without a current user' do
      allow(helper).to receive(:current_user).and_return(nil)
      expect(::Preloaders::UserMaxAccessLevelInProjectsPreloader)
        .not_to receive(:new).with([parent_project], user)

      helper.preload_hierarchy_authorization([child], [:hierarchy])
    end

    it 'does nothing when no work item has a parent' do
      expect(::Preloaders::UserMaxAccessLevelInProjectsPreloader)
        .not_to receive(:new).with([orphan.project], user)

      helper.preload_hierarchy_authorization([orphan], [:hierarchy])
    end
  end

  describe '#resolve_namespace_resource_parent!' do
    let_it_be(:group) { create(:group, :private, developers: user) }
    let_it_be(:project) { create(:project, :private, group: group) }

    let(:helper) { Class.new.include(API::Helpers).include(described_class).new }

    before do
      allow(helper).to receive_messages(initial_current_user: user, authenticate_non_public?: false)
      allow(helper).to receive(:not_found!).and_raise('not found')
    end

    it 'resolves a project path to the project and sets it for the lazy project context' do
      expect(helper.resolve_namespace_resource_parent!(project.full_path)).to eq(project)
      expect(helper.instance_variable_get(:@project)).to eq(project)
    end

    it 'resolves a group path without setting a project' do
      expect(helper.resolve_namespace_resource_parent!(group.full_path)).to eq(group)
      expect(helper.instance_variable_get(:@project)).to be_nil
    end

    it 'does not set a project the user cannot read' do
      allow(helper).to receive(:current_user).and_return(create(:user))

      expect { helper.resolve_namespace_resource_parent!(project.full_path) }.to raise_error('not found')
      expect(helper.instance_variable_get(:@project)).to be_nil
    end
  end

  describe '#resolve_group_access!' do
    let_it_be(:public_group) { create(:group, :public) }
    let_it_be(:private_group) { create(:group, :private) }

    let(:helper) { Class.new.include(API::Helpers).include(described_class).new }

    before do
      allow(helper).to receive(:authenticate_non_public?).and_return(false)
      allow(helper).to receive(:unauthorized!).and_raise('unauthorized')
      allow(helper).to receive(:not_found!).and_raise('not found')
    end

    it 'returns a public group to a non-member and sets it for the lazy namespace context' do
      expect(helper.resolve_group_access!(public_group)).to eq(public_group)
      expect(helper.instance_variable_get(:@group)).to eq(public_group)
    end

    context 'when the user cannot read the group' do
      it 'returns not found but still sets the group for the lazy namespace context' do
        expect { helper.resolve_group_access!(private_group) }.to raise_error('not found')
        expect(helper.instance_variable_get(:@group)).to eq(private_group)
      end

      it 'returns unauthorized to anonymous users when the route requires authentication for non-public resources' do
        allow(helper).to receive_messages(current_user: nil, authenticate_non_public?: true)

        expect { helper.resolve_group_access!(private_group) }.to raise_error('unauthorized')
      end
    end
  end
end
