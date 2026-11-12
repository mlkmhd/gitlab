# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Environments::DestroyBudget, :clean_gitlab_redis_rate_limiting, feature_category: :continuous_delivery do
  subject(:budget) { described_class.new(user: user, max_rows: 3) }

  let_it_be(:user) { create(:user) }

  describe '#stop_reason' do
    it 'is nil while the next batch fits the cap and time remains' do
      budget.charge(2)

      expect(budget.stop_reason(batch_size: 1)).to be_nil
    end

    context 'when the next batch would pass the cap' do
      it 'is incomplete' do
        budget.charge(2)

        expect(budget.stop_reason(batch_size: 2)).to eq(:incomplete)
      end
    end

    context 'when no batch has run yet' do
      it 'lets a batch larger than the cap run' do
        expect(budget.stop_reason(batch_size: 4)).to be_nil
      end
    end

    context 'when the runtime is spent' do
      subject(:budget) { described_class.new(user: user, max_runtime: 0) }

      it 'is incomplete' do
        expect(budget.stop_reason(batch_size: 1)).to eq(:incomplete)
      end
    end

    context 'with the rows rate limit' do
      before do
        stub_application_setting(environment_delete_rows_limit_per_user: 2)
      end

      it 'caps the rows at a limit below the cap' do
        budget.charge(1)

        expect(budget.stop_reason(batch_size: 2)).to eq(:incomplete)
      end

      it 'is throttled once a charge exceeds the limit' do
        budget.charge(3)

        expect(budget.stop_reason(batch_size: 1)).to eq(:throttled)
      end

      it 'is throttled before any charge when an earlier budget exceeded the limit' do
        described_class.new(user: user).charge(3)

        expect(budget.stop_reason(batch_size: 1)).to eq(:throttled)
      end

      context 'when the limit is disabled' do
        before do
          stub_application_setting(environment_delete_rows_limit_per_user: 0)
        end

        it 'keeps its cap' do
          budget.charge(1)

          expect(budget.stop_reason(batch_size: 2)).to be_nil
        end
      end

      context 'when rate_limit_environment_delete_rows is disabled' do
        before do
          stub_feature_flags(rate_limit_environment_delete_rows: false)
        end

        it 'keeps its cap' do
          budget.charge(1)

          expect(budget.stop_reason(batch_size: 2)).to be_nil
        end
      end

      context 'without a user' do
        let(:user) { nil }

        it 'is never throttled and keeps its cap', :aggregate_failures do
          budget.charge(1)
          expect(budget.stop_reason(batch_size: 2)).to be_nil

          budget.charge(2)
          expect(budget.stop_reason(batch_size: 1)).to eq(:incomplete)
        end
      end
    end
  end
end
