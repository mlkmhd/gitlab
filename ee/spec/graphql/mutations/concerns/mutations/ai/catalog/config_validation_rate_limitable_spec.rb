# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Ai::Catalog::ConfigValidationRateLimitable, :clean_gitlab_redis_rate_limiting,
  :freeze_time, feature_category: :ai_catalog_curation do
  let_it_be(:user) { create(:user) }

  let(:rate_limited_class) do
    mod = described_class

    Class.new do
      include mod

      attr_reader :context

      def initialize(context)
        @context = context
      end

      def current_user
        context[:current_user]
      end

      def check
        config_validation_rate_limited?
      end
    end
  end

  def limited_for?(user)
    rate_limited_class.new({ current_user: user }).check
  end

  describe '#config_validation_rate_limited?' do
    it 'is false for 30 calls each minute, then true' do
      30.times { expect(limited_for?(user)).to be(false) }

      expect(limited_for?(user)).to be(true)
    end
  end
end
