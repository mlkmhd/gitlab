# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Helpers::WorkItems::HierarchyActions, feature_category: :portfolio_management do
  # `freeze: false` is required in this spec: the bare helper instance is a non-AR subject that
  # cannot be deep-frozen. Do not convert it to `let_it_be_with_reload`/`refind`.
  let_it_be(:helper, freeze: false) do
    Class.new
      .include(API::Helpers)
      .include(API::Helpers::WorkItems::Authorization)
      .include(API::Helpers::WorkItems::Preloads)
      .include(API::Helpers::WorkItems::HierarchyFinders)
      .include(described_class)
      .new
  end

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :private, reporters: user) }
  let_it_be(:parent_work_item) { create(:work_item, project: project) }

  before do
    allow(helper).to receive_messages(current_user: user, params: {})
    allow(helper).to receive(:render_child_response)
  end

  describe '#attach_child_work_item!' do
    subject(:attach) { helper.attach_child_work_item!(project, parent_work_item.iid, child.id) }

    context 'when the user can read the child' do
      let(:child) { create(:work_item, :task, project: project) }

      it 'passes the child to the service' do
        expect(::WorkItems::ParentLinks::CreateService).to receive(:new)
          .with(parent_work_item, user, { target_issuable: child })
          .and_call_original

        attach
      end
    end

    context 'when the user cannot read the child' do
      let(:child) { create(:work_item, :task, project: create(:project, :private)) }

      it 'returns 404 without calling the service' do
        halted = Class.new(StandardError)
        expect(helper).to receive(:render_api_error!)
          .with(API::Helpers::WorkItems::HierarchyFinders::CHILD_NOT_FOUND_MESSAGE, 404)
          .and_raise(halted)
        expect(::WorkItems::ParentLinks::CreateService).not_to receive(:new)

        expect { attach }.to raise_error(halted)
      end
    end
  end
end
