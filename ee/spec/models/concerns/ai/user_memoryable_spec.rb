# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::UserMemoryable, feature_category: :duo_agent_platform do
  # Test through NamespaceUserMemory as a concrete implementation
  let_it_be(:user) { create(:user) }
  let_it_be(:namespace) { create(:group) }

  subject(:user_memory) { build(:namespace_ai_user_memory, user: user, namespace: namespace) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:content) }
    it { is_expected.to validate_length_of(:content).is_at_most(Ai::UserMemoryable::MAX_CONTENT_LENGTH) }

    it 'rejects blank content' do
      user_memory.content = '   '
      expect(user_memory).not_to be_valid
    end
  end
end
