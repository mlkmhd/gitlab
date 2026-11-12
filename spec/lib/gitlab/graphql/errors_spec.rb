# frozen_string_literal: true

require 'fast_spec_helper'
require 'graphql'

RSpec.describe Gitlab::Graphql::Errors, feature_category: :api do
  describe described_class::RateLimitedError do
    it 'serializes the given limit and its retry interval' do
      allow(Gitlab::ApplicationRateLimiter).to receive(:period_for)
        .with(:search_rate_limit_unauthenticated).and_return(90)

      error = described_class.new('Search throttled', limit: :search_rate_limit_unauthenticated)

      expect(error.to_h).to eq(
        'message' => 'Search throttled',
        'extensions' => {
          'error_type' => 'rate_limited',
          'limit' => 'search_rate_limit_unauthenticated',
          'retry_after_seconds' => 90
        }
      )
    end
  end

  # Execution errors are returned to the client as GraphQL errors instead of
  # being rescued by GraphqlController as internal server errors.
  describe 'member bulk update errors' do
    it 'are GraphQL execution errors', :aggregate_failures do
      expect(described_class::InvalidMembersError).to be < described_class::BaseError
      expect(described_class::InvalidMemberCountError).to be < described_class::BaseError
      expect(described_class::BaseError).to be < GraphQL::ExecutionError
    end
  end
end
