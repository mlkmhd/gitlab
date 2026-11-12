# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ServiceDesk::PaidNamespaceProbation, :saas_gitlab_com_subscriptions, :freeze_time, :request_store,
  feature_category: :service_desk do
  let_it_be(:free_plan) { create(:free_plan) }
  let_it_be(:premium_plan) { create(:premium_plan) }
  let_it_be_with_reload(:root_namespace) { create(:group_with_plan, plan: :premium_plan) }

  shared_context 'when on self-managed' do
    before do
      stub_saas_features(gitlab_com_subscriptions: false)
    end
  end

  def subscribed(ago)
    root_namespace.gitlab_subscription.update_column(:created_at, ago)
  end

  def add_history(hosted_plan:, **attributes)
    create(:gitlab_subscription_history, namespace: root_namespace, hosted_plan: hosted_plan, **attributes)
  end

  describe '.available?' do
    subject { described_class.available? }

    it { is_expected.to be(true) }

    context 'when on self-managed' do
      include_context 'when on self-managed'

      it { is_expected.to be(false) }
    end
  end

  describe '.configurable?' do
    subject { described_class.configurable? }

    context 'when the feature flag is enabled globally' do
      it { is_expected.to be(true) }
    end

    context 'when the feature flag is enabled only for some namespaces' do
      before do
        stub_feature_flags(service_desk_paid_namespace_probation: root_namespace)
      end

      it { is_expected.to be(false) }
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(service_desk_paid_namespace_probation: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when on self-managed' do
      include_context 'when on self-managed'

      it { is_expected.to be(false) }
    end
  end

  describe '#active?' do
    subject(:active) { described_class.new(root_namespace).active? }

    context 'with a subscription created directly on a paid plan' do
      it 'is active within the probation period' do
        subscribed((7.days - 1.minute).ago)

        expect(active).to be(true)
      end

      it 'is not active once the probation period has passed' do
        subscribed((7.days + 1.minute).ago)

        expect(active).to be(false)
      end
    end

    context 'with a subscription created outside the probation period' do
      before do
        subscribed(2.years.ago)
      end

      it 'is active after an upgrade from the free plan' do
        add_history(hosted_plan: free_plan)

        expect(active).to be(true)
      end

      it 'is active after a trial converts to a paid plan' do
        add_history(hosted_plan: premium_plan, trial: true)

        expect(active).to be(true)
      end

      it 'is active again after returning from the free plan' do
        add_history(hosted_plan: premium_plan, created_at: 1.month.ago)
        add_history(hosted_plan: free_plan)

        expect(active).to be(true)
      end

      it 'is not active when the last upgrade is outside the probation period' do
        add_history(hosted_plan: free_plan, created_at: 8.days.ago)

        expect(active).to be(false)
      end

      it 'is not active after a renewal' do
        add_history(hosted_plan: premium_plan)

        expect(active).to be(false)
      end

      it 'is not active after an Ultimate trial for a paying customer' do
        add_history(hosted_plan: create(:ultimate_trial_paid_customer_plan), trial: true)

        expect(active).to be(false)
      end
    end

    context 'with free, trial, and open source plans' do
      where(:plan_name) { %w[free premium_trial ultimate_trial opensource] }

      with_them do
        before do
          root_namespace.gitlab_subscription.update_column(
            :hosted_plan_name_uid, ::GitlabSubscriptions::SystemDefined::Plan.find_by(name: plan_name).id
          )
        end

        it 'leaves them on their own plan limits' do
          expect(active).to be(false)
        end
      end
    end

    context 'when the probation length is 0' do
      before do
        stub_application_setting(service_desk_paid_namespace_probation_days: 0)
      end

      it { is_expected.to be(false) }
    end

    context 'when the probation length is changed' do
      before do
        stub_application_setting(service_desk_paid_namespace_probation_days: 30)
      end

      it 'uses the configured length' do
        subscribed(29.days.ago)

        expect(active).to be(true)
      end
    end

    # Opt-outs are the allowlist for legitimate namespaces, so exercise real Flipper gates.
    context 'when the namespace is opted out of the feature flag', :clean_gitlab_redis_feature_flag,
      stub_feature_flags: false do
      before do
        Feature.enable(:service_desk_paid_namespace_probation)
        Feature.opt_out(:service_desk_paid_namespace_probation, root_namespace)
      end

      it { is_expected.to be(false) }
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(service_desk_paid_namespace_probation: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when on self-managed' do
      include_context 'when on self-managed'

      it { is_expected.to be(false) }
    end

    it 'caches the result for the request' do
      subscribed(1.year.ago)

      expect { described_class.new(root_namespace).active? }.to make_queries
      expect { described_class.new(root_namespace).active? }.not_to exceed_query_limit(0)
    end
  end
end
