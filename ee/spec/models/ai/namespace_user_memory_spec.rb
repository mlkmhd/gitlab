# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::NamespaceUserMemory, feature_category: :duo_agent_platform do
  let_it_be(:user) { create(:user) }
  let_it_be(:namespace) { create(:group) }

  subject(:user_memory) { described_class.new(user: user, namespace: namespace, content: 'I prefer concise responses') }

  describe 'associations' do
    it { is_expected.to belong_to(:user).required }
    it { is_expected.to belong_to(:namespace).required.inverse_of(:ai_user_memories) }
  end

  describe 'validations' do
    it { is_expected.to validate_uniqueness_of(:user_id).scoped_to(:namespace_id) }

    context 'when namespace is a subgroup' do
      it 'is invalid' do
        subgroup = create(:group, parent: namespace)
        memory = described_class.new(user: user, namespace: subgroup, content: 'test')
        expect(memory).not_to be_valid
        expect(memory.errors[:namespace]).to include(_('must be a top-level group'))
      end
    end

    context 'when namespace is a user namespace' do
      it 'is invalid' do
        memory = described_class.new(user: user, namespace: create(:namespace), content: 'test')
        expect(memory).not_to be_valid
        expect(memory.errors[:namespace]).to include(_('must be a top-level group'))
      end
    end
  end

  describe 'uniqueness' do
    before do
      user_memory.save!
    end

    it 'does not allow duplicate memories for the same user and namespace' do
      duplicate = described_class.new(user: user, namespace: namespace, content: 'Another memory')
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same user in different namespaces' do
      other_namespace = create(:group)
      other_memory = described_class.new(user: user, namespace: other_namespace, content: 'Different group memory')
      expect { other_memory.save! }.not_to raise_error
    end
  end
end
