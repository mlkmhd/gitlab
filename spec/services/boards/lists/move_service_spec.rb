# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boards::Lists::MoveService, feature_category: :planning_views do
  describe '#execute' do
    context 'when board parent is a project' do
      let_it_be(:project) { create(:project) }
      let_it_be(:board)   { create(:board, project: project) }
      let_it_be(:user)    { create(:user) }

      let(:parent) { project }

      it_behaves_like 'lists move service'
    end

    context 'when board parent is a group' do
      let_it_be(:group) { create(:group) }
      let_it_be(:board)   { create(:board, group: group) }
      let_it_be(:user)    { create(:user) }

      let(:parent) { group }

      it_behaves_like 'lists move service'
    end
  end
end
