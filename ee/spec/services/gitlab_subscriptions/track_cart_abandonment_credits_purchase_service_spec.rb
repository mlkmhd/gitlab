# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::TrackCartAbandonmentCreditsPurchaseService, feature_category: :subscription_management do
  let_it_be(:user) { create(:user, onboarding_status_email_opt_in: true) }
  let_it_be(:namespace) { create(:namespace) }

  let(:monthly_commitment_credits) { 100 }
  let(:cached_credits) { 500 }
  let(:fetch_response) { ServiceResponse.success(payload: { total_credits: cached_credits }) }

  subject(:service) do
    described_class.new(
      user: user,
      namespace: namespace,
      monthly_commitment_credits: monthly_commitment_credits
    )
  end

  def stub_cached_fetch(namespace_id, response)
    allow(GitlabSubscriptions::FetchMonthlyCommitmentService)
      .to receive(:new).with(namespace_id: namespace_id, cache_mode: :read)
      .and_return(instance_double(GitlabSubscriptions::FetchMonthlyCommitmentService, execute: response))
  end

  before do
    stub_cached_fetch(namespace.id, fetch_response)
  end

  describe '#execute' do
    context 'when user has opted in' do
      it 'enqueues the credits purchase worker with the cached monthly commitment' do
        expect(GitlabSubscriptions::CartAbandonmentCreditsPurchaseWorker)
          .to receive(:perform_in)
          .with(3.hours, user.id, namespace.id, cached_credits)

        result = service.execute

        expect(result).to be_success
      end

      context 'when the monthly commitment is unavailable' do
        let(:fetch_response) { ServiceResponse.error(message: 'error', payload: { total_credits: 0 }) }

        it 'does not enqueue the worker and returns error' do
          expect(GitlabSubscriptions::CartAbandonmentCreditsPurchaseWorker).not_to receive(:perform_in)

          result = service.execute

          expect(result).to be_error
          expect(result.message).to eq('Monthly commitment unavailable')
        end
      end

      context 'when the client raises a response error', :use_clean_rails_memory_store_caching do
        before do
          allow(GitlabSubscriptions::FetchMonthlyCommitmentService).to receive(:new).and_call_original
          allow_next_instance_of(Gitlab::SubscriptionPortal::SubscriptionUsageClient) do |client|
            allow(client).to receive(:get_monthly_commitment)
              .and_raise(Gitlab::SubscriptionPortal::SubscriptionUsageClient::ResponseError)
          end
        end

        it 'does not enqueue the worker or track the error again, and returns error' do
          expect(GitlabSubscriptions::CartAbandonmentCreditsPurchaseWorker).not_to receive(:perform_in)
          expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

          result = service.execute

          expect(result).to be_error
          expect(result.message).to eq('Monthly commitment unavailable')
        end
      end

      context 'when the request to CustomersDot fails', :use_clean_rails_memory_store_caching do
        let(:error) { Net::ReadTimeout.new }

        before do
          allow(GitlabSubscriptions::FetchMonthlyCommitmentService).to receive(:new).and_call_original
          allow_next_instance_of(Gitlab::SubscriptionPortal::SubscriptionUsageClient) do |client|
            allow(client).to receive(:get_monthly_commitment).and_raise(error)
          end
        end

        it 'tracks the error, does not enqueue the worker, and returns error' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error, namespace_id: namespace.id)
          expect(GitlabSubscriptions::CartAbandonmentCreditsPurchaseWorker).not_to receive(:perform_in)

          result = service.execute

          expect(result).to be_error
          expect(result.message).to eq('Monthly commitment unavailable')
        end
      end

      context 'when cart_abandonment_server_side_credits is enabled for a single group' do
        let_it_be(:group) { create(:group) }
        let_it_be(:other_group) { create(:group) }

        before do
          stub_feature_flags(cart_abandonment_server_side_credits: group)
          stub_cached_fetch(group.id, fetch_response)
        end

        def service_for(target)
          described_class.new(
            user: user,
            namespace: Namespace.find(target.id),
            monthly_commitment_credits: monthly_commitment_credits
          )
        end

        it 'uses the cached monthly commitment for that group' do
          expect(GitlabSubscriptions::CartAbandonmentCreditsPurchaseWorker)
            .to receive(:perform_in)
            .with(3.hours, user.id, group.id, cached_credits)

          expect(service_for(group).execute).to be_success
        end

        it 'uses the given monthly commitment for other groups' do
          expect(GitlabSubscriptions::FetchMonthlyCommitmentService).not_to receive(:new)
          expect(GitlabSubscriptions::CartAbandonmentCreditsPurchaseWorker)
            .to receive(:perform_in)
            .with(3.hours, user.id, other_group.id, monthly_commitment_credits)

          expect(service_for(other_group).execute).to be_success
        end
      end

      context 'when cart_abandonment_server_side_credits is disabled' do
        before do
          stub_feature_flags(cart_abandonment_server_side_credits: false)
        end

        it 'enqueues the credits purchase worker with the given monthly commitment' do
          expect(GitlabSubscriptions::FetchMonthlyCommitmentService).not_to receive(:new)
          expect(GitlabSubscriptions::CartAbandonmentCreditsPurchaseWorker)
            .to receive(:perform_in)
            .with(3.hours, user.id, namespace.id, monthly_commitment_credits)

          result = service.execute

          expect(result).to be_success
        end
      end
    end

    context 'when user has not opted in' do
      let(:user) { create(:user, onboarding_status_email_opt_in: false) }

      it 'does not fetch the monthly commitment or enqueue the worker, and returns error' do
        expect(GitlabSubscriptions::FetchMonthlyCommitmentService).not_to receive(:new)
        expect(GitlabSubscriptions::CartAbandonmentCreditsPurchaseWorker).not_to receive(:perform_in)

        result = service.execute

        expect(result).to be_error
        expect(result.message).to eq('User opt-in required to track credits purchase')
      end
    end
  end
end
