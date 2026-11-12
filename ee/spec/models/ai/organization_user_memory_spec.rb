# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::OrganizationUserMemory, feature_category: :duo_agent_platform do
  let_it_be(:user) { create(:user) }
  let_it_be(:organization) { create(:organization) }

  subject(:user_memory) do
    described_class.new(user: user, organization: organization, content: 'I prefer concise responses')
  end

  describe 'associations' do
    it { is_expected.to belong_to(:user).required }
    it { is_expected.to belong_to(:organization).required.class_name('Organizations::Organization').inverse_of(:ai_user_memories) }
  end

  describe 'validations' do
    it { is_expected.to validate_uniqueness_of(:user_id).scoped_to(:organization_id) }
  end

  describe 'uniqueness' do
    before do
      user_memory.save!
    end

    it 'does not allow duplicate memories for the same user and organization' do
      duplicate = described_class.new(user: user, organization: organization, content: 'Another memory')
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same user in different organizations' do
      other_org = create(:organization)
      other_memory = described_class.new(user: user, organization: other_org, content: 'Different org memory')
      expect { other_memory.save! }.not_to raise_error
    end
  end
end
