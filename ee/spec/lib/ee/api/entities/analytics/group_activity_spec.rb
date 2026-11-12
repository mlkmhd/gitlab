# frozen_string_literal: true

require 'fast_spec_helper'
require 'grape_entity'

RSpec.describe ::API::Entities::Analytics::GroupActivity, feature_category: :value_stream_management do
  let(:count) { 10 }

  shared_examples 'exposes count' do |count_type, entity|
    let(:too_large) { false }
    let(:calculator) do
      instance_double(::Analytics::GroupActivityCalculator, count_type => count, too_large?: too_large)
    end

    subject(:entity_representation) { entity.new(calculator).as_json }

    it "exposes #{count_type}" do
      expect(entity_representation).to eq({ count_type => count })
    end

    context 'when the count is too large' do
      let(:too_large) { true }

      it 'exposes too_large and no count' do
        expect(entity_representation).to eq({ count_type => nil, too_large: true })
      end
    end
  end

  context 'issues count' do
    it_behaves_like 'exposes count',
      :issues_count,
      ::API::Entities::Analytics::GroupActivity::IssuesCount
  end

  context 'merge requests count' do
    it_behaves_like 'exposes count',
      :merge_requests_count,
      ::API::Entities::Analytics::GroupActivity::MergeRequestsCount
  end

  context 'new members count' do
    it_behaves_like 'exposes count',
      :new_members_count,
      ::API::Entities::Analytics::GroupActivity::NewMembersCount
  end
end
