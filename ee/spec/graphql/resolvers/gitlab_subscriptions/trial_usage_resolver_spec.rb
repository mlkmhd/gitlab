# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::GitlabSubscriptions::TrialUsageResolver, :clean_gitlab_redis_rate_limiting,
  feature_category: :consumables_cost_management do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }

  let(:subscription_usage_client) { instance_double(Gitlab::SubscriptionPortal::SubscriptionUsageClient) }
  let(:trial_usage_response) do
    {
      success: true,
      trialUsage: {
        activeTrial: {
          startDate: '2026-02-01',
          endDate: '2026-03-03'
        },
        usersUsage: {
          creditsUsed: 45.8,
          totalUsersUsingCredits: 3
        }
      }
    }
  end

  before_all do
    group.add_owner(user)
  end

  before do
    stub_ee_application_setting(should_check_namespace_plan: true)
    allow(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to receive(:new).and_return(subscription_usage_client)
    allow(subscription_usage_client).to receive(:get_trial_usage).and_return(trial_usage_response)
  end

  describe '#resolve' do
    context 'with namespace_path argument' do
      it 'returns a TrialsUsage::Base instance' do
        result = resolve_trial_usage(namespace_path: group.full_path)

        expect(result).to be_a(GitlabSubscriptions::TrialsUsage::Base)
        expect(result.namespace).to eq(group)
      end

      it 'initializes SubscriptionUsageClient with namespace_id' do
        expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to receive(:new)
          .with(namespace_id: group.id)
          .and_return(subscription_usage_client)

        resolve_trial_usage(namespace_path: group.full_path)
      end

      it_behaves_like 'subscription usage rate limited resolver' do
        let(:rate_limit_user) { user }
        let(:rate_limit_namespace) { group }
        let(:expected_result_class) { GitlabSubscriptions::TrialsUsage::Base }

        def resolve_rate_limited
          resolve_trial_usage(namespace_path: group.full_path)
        end

        def resolve_unauthorized
          resolve_trial_usage(namespace_path: group.full_path, current_user: create(:user))
        end
      end
    end

    context 'with organization_id argument', :saas do
      let_it_be(:organization) { create(:organization) }
      let_it_be(:organization_owner) { create(:user, owner_of: organization) }
      let_it_be(:nominated_group) { create(:group, organization: organization) }

      let(:organization_gid) { organization.to_global_id.to_s }

      before_all do
        create(:organization_gitlab_subscription,
          organization: organization,
          gitlab_subscription: create(:gitlab_subscription, namespace: nominated_group))
      end

      it 'returns a TrialsUsage::Base instance for the organization' do
        result = resolve_trial_usage({ organization_id: organization_gid }, current_user: organization_owner)

        expect(result).to be_a(GitlabSubscriptions::TrialsUsage::Base)
        expect(result.organization).to eq(organization)
        expect(result.namespace).to eq(nominated_group)
      end

      it "initializes SubscriptionUsageClient with the nominated group's namespace_id" do
        expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to receive(:new)
          .with(namespace_id: nominated_group.id)
          .and_return(subscription_usage_client)

        resolve_trial_usage({ organization_id: organization_gid }, current_user: organization_owner)
      end

      it 'raises an error when the user owns the nominated group but not the organization' do
        nominated_group_owner = create(:user, owner_of: nominated_group)

        expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ResourceNotAvailable) do
          resolve_trial_usage({ organization_id: organization_gid }, current_user: nominated_group_owner)
        end
      end

      context 'when organization_billing is disabled' do
        before do
          stub_feature_flags(organization_billing: false)
        end

        it 'raises an error' do
          expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ResourceNotAvailable) do
            resolve_trial_usage({ organization_id: organization_gid }, current_user: organization_owner)
          end
        end
      end

      context 'when the organization does not exist' do
        let(:organization_gid) { "gid://gitlab/Organizations::Organization/#{non_existing_record_id}" }

        it 'raises an error' do
          expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ResourceNotAvailable) do
            resolve_trial_usage({ organization_id: organization_gid }, current_user: organization_owner)
          end
        end
      end
    end

    context 'without namespace_path argument (instance)' do
      let_it_be(:admin) { create(:admin) }
      let(:license) { create(:license) }

      before do
        allow(License).to receive(:current).and_return(license)
      end

      it 'returns a TrialsUsage::Base instance for instance subscription', :enable_admin_mode do
        result = resolve_trial_usage(current_user: admin)

        expect(result).to be_a(GitlabSubscriptions::TrialsUsage::Base)
      end

      it 'initializes SubscriptionUsageClient with license_key', :enable_admin_mode do
        expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to receive(:new)
          .with(license_key: license.data)
          .and_return(subscription_usage_client)

        resolve_trial_usage(current_user: admin)
      end

      context 'when there is no current license', :enable_admin_mode do
        let(:license) { nil }

        it 'builds the client without a license key' do
          expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to receive(:new)
            .with(no_args)
            .and_return(subscription_usage_client)

          resolve_trial_usage(current_user: admin)
        end
      end

      context 'with admin mode', :enable_admin_mode do
        it_behaves_like 'subscription usage rate limited resolver', namespace_actor: false do
          let(:rate_limit_user) { admin }
          let(:rate_limit_namespace) { nil }
          let(:expected_result_class) { GitlabSubscriptions::TrialsUsage::Base }

          def resolve_rate_limited
            resolve_trial_usage(current_user: admin)
          end

          def resolve_unauthorized
            resolve_trial_usage(current_user: create(:user))
          end
        end
      end

      it 'treats an explicitly null organization_id as an instance query', :enable_admin_mode do
        expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to receive(:new)
          .with(license_key: license.data)
          .and_return(subscription_usage_client)

        result = resolve_trial_usage(organization_id: nil, current_user: admin)

        expect(result.subscription_target).to eq(:instance)
        expect(result.organization).to be_nil
      end
    end
  end

  def resolve_trial_usage(args = {}, context = {})
    resolve(described_class, args: args, ctx: { current_user: args[:current_user] || user }.merge(context))
  end
end
