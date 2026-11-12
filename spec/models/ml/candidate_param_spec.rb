# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ml::CandidateParam, feature_category: :mlops do
  describe 'associations' do
    it { is_expected.to belong_to(:candidate) }
  end

  describe '.for_candidates' do
    let_it_be(:record) { create(:ml_candidate_params) }
    let_it_be(:other_record) { create(:ml_candidate_params) }

    it 'returns the params of the given candidates' do
      candidates = Ml::Candidate.id_in(record.candidate_id)

      expect(described_class.for_candidates(candidates)).to contain_exactly(record)
    end
  end
end
