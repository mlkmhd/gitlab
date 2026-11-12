# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Helpers::WorkItems::HierarchyFinders, feature_category: :portfolio_management do
  # `freeze: false` is required in this spec: the bare helper instance is a non-AR subject that
  # cannot be deep-frozen. Do not convert it to `let_it_be_with_reload`/`refind`.
  let_it_be(:helper, freeze: false) { Class.new.include(API::Helpers).include(described_class).new }
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :private, reporters: user) }

  before do
    allow(helper).to receive(:current_user).and_return(user)
  end

  describe '#find_readable_child_work_item!' do
    subject(:find_child) { helper.find_readable_child_work_item!(child_id) }

    context 'when the user can read the child' do
      let_it_be(:child) { create(:work_item, :task, project: project) }
      let(:child_id) { child.id }

      it { is_expected.to eq(child) }
    end

    shared_examples 'a missing child' do
      it 'returns the same 404 as for a missing id' do
        halted = Class.new(StandardError)
        expect(helper).to receive(:render_api_error!)
          .with(described_class::CHILD_NOT_FOUND_MESSAGE, 404)
          .and_raise(halted)

        expect { find_child }.to raise_error(halted)
      end
    end

    context 'when the user cannot read the child' do
      let(:child_id) { create(:work_item, :task, project: create(:project, :private)).id }

      it_behaves_like 'a missing child'
    end

    context 'when the child does not exist' do
      let(:child_id) { non_existing_record_id }

      it_behaves_like 'a missing child'
    end
  end
end
