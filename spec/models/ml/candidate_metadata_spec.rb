# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ml::CandidateMetadata, feature_category: :mlops do
  describe 'associations' do
    it { is_expected.to belong_to(:candidate) }
  end

  describe '.for_candidates' do
    let_it_be(:record) { create(:ml_candidate_metadata) }
    let_it_be(:other_record) { create(:ml_candidate_metadata) }

    it 'returns the metadata of the given candidates' do
      candidates = Ml::Candidate.id_in(record.candidate_id)

      expect(described_class.for_candidates(candidates)).to contain_exactly(record)
    end
  end

  describe 'uniqueness of name' do
    let_it_be(:metadata) { create(:ml_candidate_metadata, name: 'some_metadata') }
    let_it_be(:candidate) { metadata.candidate }

    it 'is unique within candidate' do
      expect do
        candidate.metadata.create!(name: 'some_metadata', value: 'blah')
      end.to raise_error.with_message(/Name 'some_metadata' already taken/)
    end
  end
end
