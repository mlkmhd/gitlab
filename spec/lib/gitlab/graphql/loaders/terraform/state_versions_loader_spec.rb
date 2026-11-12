# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Graphql::Loaders::Terraform::StateVersionsLoader, feature_category: :infrastructure_as_code do
  let_it_be(:project) { create(:project) }
  # StateVersion touches its state on create, which a frozen let_it_be record rejects.
  let_it_be_with_refind(:state) { create(:terraform_state, project: project) }
  let_it_be_with_refind(:other_state) { create(:terraform_state, project: project) }

  let_it_be(:older_version) { create(:terraform_state_version, terraform_state: state, version: 1) }
  let_it_be(:newer_version) { create(:terraform_state_version, terraform_state: state, version: 2) }
  let_it_be(:other_version) { create(:terraform_state_version, terraform_state: other_state, version: 1) }

  let(:query_context) { {} }

  def versions_for(record)
    described_class.new(query_context, record).load.load
  end

  describe '#load' do
    it 'returns the versions of the state, most recent first' do
      expect(versions_for(state)).to eq([newer_version, older_version])
    end

    it 'does not mix versions across states' do
      expect(versions_for(other_state)).to eq([other_version])
    end

    it 'loads the versions of every registered state in one query' do
      loaders = [state, other_state].map { |record| described_class.new(query_context, record) }

      expect { loaders.each { |loader| loader.load.load } }.not_to exceed_query_limit(1)
    end

    it 'does not repeat versions when the same state is registered twice' do
      loaders = Array.new(2) { described_class.new(query_context, state) }

      expect(loaders.map { |loader| loader.load.load }).to match_array([[newer_version, older_version]] * 2)
    end

    it 'does not repeat versions when separate records have the same state ID' do
      loaders = [state, Terraform::State.find(state.id)].map do |record|
        described_class.new(query_context, record)
      end

      expect(loaders.map { |loader| loader.load.load }).to match_array([[newer_version, older_version]] * 2)
    end

    it 'applies a limit per state rather than across states' do
      loaders = [state, other_state].map { |record| described_class.new(query_context, record) }

      expect(loaders.map { |loader| loader.load.limit(1).load }).to eq([[newer_version], [other_version]])
    end
  end
end
