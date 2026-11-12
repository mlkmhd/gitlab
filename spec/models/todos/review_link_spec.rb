# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Todos::ReviewLink, feature_category: :notifications do
  describe 'associations' do
    it { is_expected.to belong_to(:todo).inverse_of(:review_link).required }
    it { is_expected.to belong_to(:project).required }
    it { is_expected.to belong_to(:review).required }
  end

  it 'is keyed by the to-do item' do
    link = create(:todo_review_link)

    expect(described_class.find(link.todo_id)).to eq(link)
  end
end
