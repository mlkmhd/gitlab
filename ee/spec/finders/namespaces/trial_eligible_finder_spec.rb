# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Namespaces::TrialEligibleFinder, feature_category: :subscription_management do
  describe '#execute', :saas, :use_clean_rails_memory_store_caching do
    let_it_be(:user) { create(:user) }
    let_it_be(:free_namespace) { create(:group, name: 'Zeta', owners: user) }
    let_it_be(:premium_namespace) { create(:group_with_plan, name: 'Alpha', plan: :premium_plan, owners: user) }

    subject(:execute) { described_class.new(params).execute }

    shared_examples 'cached eligible namespaces' do
      let(:cache_key_free_namespace) { "namespaces:eligible_trials:#{free_namespace.id}" }
      let(:cache_key_premium_namespace) { "namespaces:eligible_trials:#{premium_namespace.id}" }

      let(:namespaces_response) do
        {
          free_namespace.id.to_s => GitlabSubscriptions::Trials::TRIAL_TYPES,
          premium_namespace.id.to_s => [GitlabSubscriptions::Trials::PREMIUM_TRIAL_TYPE_V2, 'gitlab_duo_pro']
        }
      end

      let(:cache_write) do
        {
          cache_key_free_namespace => namespaces_response[free_namespace.id.to_s],
          cache_key_premium_namespace => namespaces_response[premium_namespace.id.to_s]
        }
      end

      before do
        allow(Rails.cache).to receive(:exist?).with(cache_key_free_namespace).once.and_call_original
      end

      context 'when cache exists for all namespaces' do
        before do
          Rails.cache.write_multi(cache_write)
          allow(Rails.cache).to receive(:exist?).with(cache_key_premium_namespace).once.and_call_original
        end

        it { is_expected.to eq([premium_namespace, free_namespace]) }

        context 'when requested trial is not eligible' do
          let(:namespaces_response) do
            {
              free_namespace.id.to_s => ['gitlab_duo_pro'],
              premium_namespace.id.to_s => [GitlabSubscriptions::Trials::FREE_TRIAL_TYPE_V2]
            }
          end

          it { is_expected.to be_empty }
        end

        context 'when first namespace has the ultimate plan' do
          let(:cache_write) { { cache_key_premium_namespace => namespaces_response[premium_namespace.id.to_s] } }

          before do
            create(:gitlab_subscription, :ultimate, namespace: free_namespace)
          end

          it { is_expected.to eq([premium_namespace]) }
        end
      end

      context 'when cache is not complete' do
        let(:cache_key_failed_premium_namespace) { "namespaces:eligible_trials:failed:#{premium_namespace.id}" }
        let(:healthy_response) { { success: true, data: { namespaces: namespaces_response } } }

        before do
          Rails.cache.write(cache_key_free_namespace, namespaces_response[free_namespace.id.to_s])

          allow(Rails.cache).to receive(:exist?).with(cache_key_premium_namespace).once.and_call_original
        end

        context 'with fail_fast' do
          let(:params) { super().merge(fail_fast: true) }

          before do
            allow(Gitlab::SubscriptionPortal::Client)
              .to receive(:namespace_eligible_trials)
                    .with(
                      namespace_ids: containing_exactly(free_namespace.id, premium_namespace.id),
                      timeout: 1.second,
                      max_retries: 0
                    )
                    .and_return(response)
          end

          context 'with a successful CustomersDot query', :aggregate_failures do
            let(:response) { healthy_response }

            it 'caches the query response' do
              expect(Rails.cache).to receive(:write_multi).with(
                {
                  cache_key_free_namespace => namespaces_response[free_namespace.id.to_s],
                  cache_key_premium_namespace => namespaces_response[premium_namespace.id.to_s]
                },
                expires_in: 8.hours
              ).and_call_original

              expect(execute).to eq([premium_namespace, free_namespace])
            end
          end

          context 'with an unsuccessful CustomersDot query' do
            let(:response) { { success: false } }

            it { is_expected.to be_empty }

            it 'records the failure under a separate key for a short time' do
              expect(Rails.cache).to receive(:write_multi).with(
                {
                  "namespaces:eligible_trials:failed:#{free_namespace.id}" => true,
                  cache_key_failed_premium_namespace => true
                },
                expires_in: 5.minutes
              ).and_call_original

              execute
            end

            it 'keeps the cached eligibility of every namespace' do
              execute

              expect(Rails.cache.read(cache_key_free_namespace)).to eq(namespaces_response[free_namespace.id.to_s])
              expect(Rails.cache.read(cache_key_premium_namespace)).to be_nil
            end

            it 'does not call CustomersDot again from fail-fast callers while the failure is recorded' do
              execute

              expect(Gitlab::SubscriptionPortal::Client).not_to receive(:namespace_eligible_trials)
              allow(Rails.cache).to receive(:exist?).and_call_original

              expect(described_class.new(params).execute).to eq([free_namespace])
            end

            it 'lets a later check without fail_fast call CustomersDot and find the namespaces eligible' do
              execute

              allow(Rails.cache).to receive(:exist?).and_call_original
              expect(Gitlab::SubscriptionPortal::Client)
                .to receive(:namespace_eligible_trials)
                      .with(namespace_ids: containing_exactly(free_namespace.id, premium_namespace.id))
                      .and_return(healthy_response)

              expect(described_class.new(params.except(:fail_fast)).execute).to eq([premium_namespace, free_namespace])
            end
          end

          context 'when fail_fast_cdot_trial_requests is disabled' do
            let(:response) { { success: false } }

            before do
              stub_feature_flags(fail_fast_cdot_trial_requests: false)

              allow(Gitlab::SubscriptionPortal::Client)
                .to receive(:namespace_eligible_trials)
                      .with(namespace_ids: containing_exactly(free_namespace.id, premium_namespace.id))
                      .and_return(response)
            end

            it 'uses the default HTTP options and does not cache the failure' do
              expect(Rails.cache).not_to receive(:write_multi)

              expect(execute).to be_empty
            end
          end
        end

        context 'without fail_fast' do
          before do
            allow(Gitlab::SubscriptionPortal::Client)
              .to receive(:namespace_eligible_trials)
                    .with(namespace_ids: containing_exactly(free_namespace.id, premium_namespace.id))
                    .and_return(response)
          end

          context 'with a successful CustomersDot query' do
            let(:response) { healthy_response }

            it { is_expected.to eq([premium_namespace, free_namespace]) }
          end

          context 'with an unsuccessful CustomersDot query' do
            let(:response) { { success: false } }

            it { is_expected.to be_empty }

            it 'does not cache the failure' do
              expect(Rails.cache).not_to receive(:write_multi)

              execute
            end

            it 'ignores a failure recorded by a fail-fast caller' do
              Rails.cache.write(cache_key_failed_premium_namespace, true)

              expect(Gitlab::SubscriptionPortal::Client).to receive(:namespace_eligible_trials)

              execute
            end
          end
        end
      end
    end

    context 'with user and namespace' do
      let(:params) { { user: build(:user), namespace: build(:group) } }

      it 'raises an error' do
        expect { execute }.to raise_error(ArgumentError, 'Only User or Namespace can be provided, not both')
      end
    end

    context 'with user' do
      let(:params) { { user: user } }

      it_behaves_like 'cached eligible namespaces'

      context 'when a user does not own any groups' do
        let(:params) { super().merge(user: build(:user)) }

        it { is_expected.to eq([]) }
      end
    end

    context 'with namespaces' do
      let(:params) { { namespace: [free_namespace, premium_namespace] } }

      it_behaves_like 'cached eligible namespaces'
    end
  end
end
