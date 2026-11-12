# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::RecommendReviewers::ReviewerWorkload,
  feature_category: :code_review_workflow do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }

  subject(:workload) { described_class.new([user]) }

  before_all do
    %i[unreviewed reviewed approved requested_changes].each do |state|
      create(:merge_request, source_project: project, target_project: project, source_branch: "#{state}-branch") do |mr|
        mr.merge_request_reviewers.create!(reviewer: user, state: state)
      end
    end
  end

  describe '#pending_reviews' do
    it 'counts the open review requests without a response' do
      expect(workload.pending_reviews(user)).to eq(1)
    end
  end

  describe '#responded_reviews_weights' do
    it 'weights the responded reviews at half' do
      expect(workload.responded_reviews_weights([user.id])).to eq(user.id => 2)
    end

    it 'reuses the counts of #pending_reviews' do
      workload.pending_reviews(user)

      expect { workload.responded_reviews_weights([user.id]) }.not_to exceed_query_limit(0)
    end
  end
end
