# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::FetchMonthlyCommitmentService, feature_category: :subscription_management do
  let_it_be(:namespace) { create(:namespace) }

  let(:client) { instance_double(Gitlab::SubscriptionPortal::SubscriptionUsageClient) }

  subject(:service) { described_class.new(namespace_id: namespace.id) }

  before do
    allow(Gitlab::SubscriptionPortal::SubscriptionUsageClient)
      .to receive(:new)
      .with(namespace_id: namespace.id)
      .and_return(client)
  end

  describe '#initialize' do
    it 'raises for an unknown cache mode' do
      expect { described_class.new(namespace_id: namespace.id, cache_mode: true) }
        .to raise_error(ArgumentError, 'Unknown cache mode: true')
    end
  end

  describe '#execute' do
    context 'when the client returns a successful response with credits' do
      before do
        allow(client).to receive(:get_monthly_commitment).and_return({
          success: true,
          monthlyCommitment: { totalCredits: 500 }
        })
      end

      it 'returns a success response with the total credits' do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:total_credits]).to eq(500)
      end
    end

    context 'when the client returns a successful response without totalCredits' do
      before do
        allow(client).to receive(:get_monthly_commitment).and_return({
          success: true,
          monthlyCommitment: {}
        })
      end

      it 'returns a success response with 0 credits' do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:total_credits]).to eq(0)
      end
    end

    context 'when the client returns a successful response without monthlyCommitment' do
      before do
        allow(client).to receive(:get_monthly_commitment).and_return({ success: true })
      end

      it 'returns a success response with 0 credits' do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:total_credits]).to eq(0)
      end
    end

    context 'when the client returns an unsuccessful response' do
      before do
        allow(client).to receive(:get_monthly_commitment).and_return({ success: false })
      end

      it 'returns an error response with 0 credits' do
        result = service.execute

        expect(result).to be_error
        expect(result.message).to eq('Failed to fetch monthly commitment')
        expect(result.payload[:total_credits]).to eq(0)
      end
    end

    context 'with a cache mode', :use_clean_rails_memory_store_caching do
      let(:success_response) { { success: true, monthlyCommitment: { totalCredits: 500 } } }

      before do
        allow(client).to receive(:get_monthly_commitment).and_return(success_response)
      end

      def execute(cache_mode)
        described_class.new(namespace_id: namespace.id, cache_mode: cache_mode).execute
      end

      context 'with cache_mode: :read' do
        it 'fetches from CustomersDot on a cache miss' do
          result = execute(:read)

          expect(result).to be_success
          expect(result.payload[:total_credits]).to eq(500)
        end

        it 'returns the cached value without calling CustomersDot again' do
          execute(:read)

          expect(client).not_to receive(:get_monthly_commitment)
          expect(execute(:read).payload[:total_credits]).to eq(500)
        end

        it 'caches a total of 0' do
          allow(client).to receive(:get_monthly_commitment).and_return({ success: true, monthlyCommitment: {} })
          execute(:read)

          expect(client).not_to receive(:get_monthly_commitment)
          expect(execute(:read).payload[:total_credits]).to eq(0)
        end

        it 'expires the cached value' do
          execute(:read)

          travel_to(1.hour.from_now + 1.second) do
            expect(client).to receive(:get_monthly_commitment).and_return(success_response)
            execute(:read)
          end
        end

        it 'does not cache an unsuccessful response' do
          allow(client).to receive(:get_monthly_commitment).and_return({ success: false })

          expect(execute(:read)).to be_error

          allow(client).to receive(:get_monthly_commitment).and_return({ success: true, monthlyCommitment: {} })
          expect(execute(:read)).to be_success
        end

        it 'raises client errors without caching them' do
          allow(client).to receive(:get_monthly_commitment)
            .and_raise(Gitlab::SubscriptionPortal::SubscriptionUsageClient::ResponseError)

          expect { execute(:read) }.to raise_error(Gitlab::SubscriptionPortal::SubscriptionUsageClient::ResponseError)

          allow(client).to receive(:get_monthly_commitment).and_return({ success: true, monthlyCommitment: {} })
          expect(execute(:read)).to be_success
        end
      end

      context 'with cache_mode: :refresh' do
        it 'fetches from CustomersDot and overwrites the cached value' do
          execute(:read)
          allow(client).to receive(:get_monthly_commitment)
            .and_return({ success: true, monthlyCommitment: { totalCredits: 1000 } })

          expect(execute(:refresh).payload[:total_credits]).to eq(1000)
          expect(execute(:read).payload[:total_credits]).to eq(1000)
        end
      end

      context 'with the default cache_mode: :none' do
        it 'neither reads nor writes the cache' do
          execute(:read)
          allow(client).to receive(:get_monthly_commitment)
            .and_return({ success: true, monthlyCommitment: { totalCredits: 1000 } })

          expect(service.execute.payload[:total_credits]).to eq(1000)
          expect(execute(:read).payload[:total_credits]).to eq(500)
        end
      end
    end
  end
end
