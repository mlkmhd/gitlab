# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'UpsertUserBudgetCapOverrides mutation', :clean_gitlab_redis_rate_limiting,
  feature_category: :consumables_cost_management do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }
  let_it_be(:owner) { create(:user) }
  let_it_be(:non_owner) { create(:user) }
  let_it_be(:target_user1) { create(:user) }
  let_it_be(:target_user2) { create(:user) }
  let_it_be(:root_group) { create(:group, owners: owner) }
  let_it_be(:non_member_user) { create(:user) }
  let(:namespace_path) { root_group.full_path }
  let(:overrides_input) do
    [
      {
        userId: target_user1.to_global_id.to_s,
        cap: 300.0,
        enabled: true
      },
      {
        userId: target_user2.to_global_id.to_s,
        cap: 150.0,
        enabled: false
      }
    ]
  end

  let(:mutation_input) do
    { namespace_path: namespace_path, overrides: overrides_input }
  end

  let(:mutation) do
    graphql_mutation(
      :upsert_user_budget_cap_overrides,
      mutation_input,
      <<~FIELDS
        userOverrides {
          user { id username }
          cap
          capEnabled
        }
        errors
      FIELDS
    )
  end

  let(:cdot_success_response) do
    {
      success: true,
      userBudgetCapOverrides: [
        {
          entityId: target_user1.id.to_s,
          cap: 300.0,
          capEnabled: true,
          selfManagedInstanceActivationId: nil
        },
        {
          entityId: target_user2.id.to_s,
          cap: 150.0,
          capEnabled: false,
          selfManagedInstanceActivationId: nil
        }
      ]
    }
  end

  let(:cdot_error_response) do
    {
      success: false,
      errors: ["CDot internal error"]
    }
  end

  before_all do
    root_group.add_developer(target_user1)
    root_group.add_developer(target_user2)
  end

  shared_examples 'unauthorized user' do
    it 'returns a resource not available error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include(
        /does not exist or you don't have permission/
      )
    end
  end

  context 'when SaaS (namespace scope)' do
    let(:current_user) { owner }

    context 'when user is a namespace owner' do
      before do
        allow_next_instance_of(
          Gitlab::SubscriptionPortal::SubscriptionUsageClient
        ) do |client|
          allow(client).to receive(
            :upsert_user_budget_cap_overrides
          ).and_return(cdot_success_response)
        end
      end

      it_behaves_like 'authorizing granular token permissions for GraphQL', :update_subscription_usage_cap do
        let(:user) { owner }
        let(:boundary_object) { root_group }
        let(:mutation) { graphql_mutation(:upsert_user_budget_cap_overrides, mutation_input, 'errors') }
        let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
      end

      it 'returns updated user overrides' do
        post_graphql_mutation(mutation, current_user: current_user)

        mutation_response = graphql_mutation_response(
          :upsert_user_budget_cap_overrides
        )

        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['userOverrides']).to contain_exactly(
          a_hash_including(
            'cap' => 300.0,
            'capEnabled' => true,
            'user' => a_hash_including(
              'id' => target_user1.to_global_id.to_s,
              'username' => target_user1.username
            )
          ),
          a_hash_including(
            'cap' => 150.0,
            'capEnabled' => false,
            'user' => a_hash_including(
              'id' => target_user2.to_global_id.to_s,
              'username' => target_user2.username
            )
          )
        )
      end

      it 'passes correctly formatted overrides to CDot client' do
        expected_overrides = [
          { entityId: target_user1.id.to_s, capAmount: 300.0, enabled: true },
          { entityId: target_user2.id.to_s, capAmount: 150.0, enabled: false }
        ]

        expect_next_instance_of(
          Gitlab::SubscriptionPortal::SubscriptionUsageClient
        ) do |client|
          expect(client).to receive(
            :upsert_user_budget_cap_overrides
          ).with(overrides: expected_overrides).and_return(
            cdot_success_response
          )
        end

        post_graphql_mutation(mutation, current_user: current_user)
      end

      context 'when organization_id is explicitly null' do
        let(:mutation_input) { super().merge(organization_id: nil) }

        it 'updates the namespace overrides' do
          post_graphql_mutation(mutation, current_user: current_user)

          mutation_response = graphql_mutation_response(:upsert_user_budget_cap_overrides)
          expect(mutation_response['errors']).to be_empty
          expect(mutation_response['userOverrides']).to be_present
        end
      end

      context 'when CDot returns an error' do
        before do
          allow_next_instance_of(
            Gitlab::SubscriptionPortal::SubscriptionUsageClient
          ) do |client|
            allow(client).to receive(
              :upsert_user_budget_cap_overrides
            ).and_return(cdot_error_response)
          end
        end

        it 'propagates CDot errors' do
          post_graphql_mutation(mutation, current_user: current_user)

          mutation_response = graphql_mutation_response(
            :upsert_user_budget_cap_overrides
          )

          expect(mutation_response['userOverrides']).to be_nil
          expect(mutation_response['errors']).to include(
            "CDot internal error"
          )
        end
      end
    end

    context 'when all userIds are non-existent' do
      let(:overrides_input) do
        [
          {
            userId: "gid://gitlab/User/#{non_existing_record_id}",
            cap: 100.0,
            enabled: true
          }
        ]
      end

      it 'returns an argument error with the missing user IDs' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect_graphql_errors_to_include(
          "Users not found: gid://gitlab/User/#{non_existing_record_id}"
        )
      end

      it 'does not call CDot' do
        expect(
          Gitlab::SubscriptionPortal::SubscriptionUsageClient
        ).not_to receive(:new)

        post_graphql_mutation(mutation, current_user: current_user)
      end
    end

    context 'when some userIds are valid and one is not' do
      let(:overrides_input) do
        [
          {
            userId: target_user1.to_global_id.to_s,
            cap: 300.0,
            enabled: true
          },
          {
            userId: "gid://gitlab/User/#{non_existing_record_id}",
            cap: 100.0,
            enabled: true
          }
        ]
      end

      it 'rejects the entire batch with the missing user IDs' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect_graphql_errors_to_include(
          "Users not found: gid://gitlab/User/#{non_existing_record_id}"
        )
      end
    end

    context 'when user is not a member of the namespace' do
      let(:overrides_input) do
        [
          {
            userId: non_member_user.to_global_id.to_s,
            cap: 100.0,
            enabled: true
          }
        ]
      end

      it 'returns an argument error with the user global ID' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect_graphql_errors_to_include(
          "Users are not part of the namespace: #{non_member_user.to_global_id}"
        )
      end

      it 'does not call CDot' do
        expect(
          Gitlab::SubscriptionPortal::SubscriptionUsageClient
        ).not_to receive(:new)

        post_graphql_mutation(mutation, current_user: current_user)
      end
    end

    context 'when overrides exceed the maximum limit' do
      let(:overrides_input) do
        Array.new(201) do |i|
          {
            userId: target_user1.to_global_id.to_s,
            cap: i.to_f,
            enabled: true
          }
        end
      end

      it 'returns an argument error' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect_graphql_errors_to_include(
          "Cannot upsert more than 200 overrides at once"
        )
      end
    end

    context 'when user is not a namespace owner' do
      let(:current_user) { non_owner }

      it_behaves_like 'unauthorized user'
    end

    context 'with empty overrides array' do
      let(:overrides_input) { [] }

      before do
        allow_next_instance_of(
          Gitlab::SubscriptionPortal::SubscriptionUsageClient
        ) do |client|
          allow(client).to receive(
            :upsert_user_budget_cap_overrides
          ).and_return({ success: true, userBudgetCapOverrides: [] })
        end
      end

      it 'succeeds with empty result' do
        post_graphql_mutation(mutation, current_user: current_user)

        mutation_response = graphql_mutation_response(
          :upsert_user_budget_cap_overrides
        )

        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['userOverrides']).to eq([])
      end
    end

    context 'with duplicate userIds in same batch' do
      let(:overrides_input) do
        [
          {
            userId: target_user1.to_global_id.to_s,
            cap: 300.0,
            enabled: true
          },
          {
            userId: target_user1.to_global_id.to_s,
            cap: 500.0,
            enabled: false
          }
        ]
      end

      before do
        allow_next_instance_of(
          Gitlab::SubscriptionPortal::SubscriptionUsageClient
        ) do |client|
          allow(client).to receive(
            :upsert_user_budget_cap_overrides
          ).and_return(cdot_success_response)
        end
      end

      it 'passes through to CDot without dedup' do
        expect_next_instance_of(
          Gitlab::SubscriptionPortal::SubscriptionUsageClient
        ) do |client|
          expect(client).to receive(
            :upsert_user_budget_cap_overrides
          ).with(
            overrides: [
              {
                entityId: target_user1.id.to_s,
                capAmount: 300.0,
                enabled: true
              },
              {
                entityId: target_user1.id.to_s,
                capAmount: 500.0,
                enabled: false
              }
            ]
          ).and_return(cdot_success_response)
        end

        post_graphql_mutation(mutation, current_user: current_user)
      end
    end

    context 'when overrides are identified by username' do
      let(:overrides_input) do
        [
          { username: target_user1.username, cap: 300.0, enabled: true },
          { userId: target_user2.to_global_id.to_s, cap: 150.0, enabled: false }
        ]
      end

      it 'resolves usernames to user IDs and passes them to CDot' do
        expected_overrides = [
          { entityId: target_user1.id.to_s, capAmount: 300.0, enabled: true },
          { entityId: target_user2.id.to_s, capAmount: 150.0, enabled: false }
        ]

        expect_next_instance_of(
          Gitlab::SubscriptionPortal::SubscriptionUsageClient
        ) do |client|
          expect(client).to receive(
            :upsert_user_budget_cap_overrides
          ).with(overrides: expected_overrides).and_return(
            cdot_success_response
          )
        end

        post_graphql_mutation(mutation, current_user: current_user)

        mutation_response = graphql_mutation_response(
          :upsert_user_budget_cap_overrides
        )

        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['userOverrides']).to contain_exactly(
          a_hash_including('user' => a_hash_including('username' => target_user1.username)),
          a_hash_including('user' => a_hash_including('username' => target_user2.username))
        )
      end

      it 'resolves usernames in a single query' do
        allow_next_instance_of(
          Gitlab::SubscriptionPortal::SubscriptionUsageClient
        ) do |client|
          allow(client).to receive(
            :upsert_user_budget_cap_overrides
          ).and_return(cdot_success_response)
        end

        control = ActiveRecord::QueryRecorder.new do
          post_graphql_mutation(mutation, current_user: current_user)
        end

        expect(control.log.count { |sql| sql.include?('LOWER("users"."username")') }).to eq(1)
      end

      context 'when usernames differ in case' do
        let(:overrides_input) do
          [{ username: target_user1.username.upcase, cap: 300.0, enabled: true }]
        end

        it 'resolves the user case-insensitively' do
          expect_next_instance_of(
            Gitlab::SubscriptionPortal::SubscriptionUsageClient
          ) do |client|
            expect(client).to receive(
              :upsert_user_budget_cap_overrides
            ).with(
              overrides: [{ entityId: target_user1.id.to_s, capAmount: 300.0, enabled: true }]
            ).and_return(cdot_success_response)
          end

          post_graphql_mutation(mutation, current_user: current_user)
        end
      end

      context 'when a username does not exist' do
        let(:overrides_input) do
          [
            { username: target_user1.username, cap: 300.0, enabled: true },
            { username: 'does-not-exist', cap: 100.0, enabled: true }
          ]
        end

        it 'rejects the entire batch with the missing usernames' do
          post_graphql_mutation(mutation, current_user: current_user)

          expect_graphql_errors_to_include('Users not found: does-not-exist')
        end

        it 'does not call CDot' do
          expect(
            Gitlab::SubscriptionPortal::SubscriptionUsageClient
          ).not_to receive(:new)

          post_graphql_mutation(mutation, current_user: current_user)
        end
      end

      context 'when the user is not a member of the namespace' do
        let(:overrides_input) do
          [{ username: non_member_user.username, cap: 100.0, enabled: true }]
        end

        it 'returns an argument error with the submitted username' do
          post_graphql_mutation(mutation, current_user: current_user)

          expect_graphql_errors_to_include(
            "Users are not part of the namespace: #{non_member_user.username}"
          )
        end
      end
    end
  end

  context 'when self-managed (instance scope)' do
    let(:mutation_input) { { overrides: overrides_input } }
    let(:namespace_path) { nil }

    context 'when user is an instance admin', :enable_admin_mode do
      let(:current_user) { admin }

      before do
        allow_next_instance_of(
          Gitlab::SubscriptionPortal::SubscriptionUsageClient
        ) do |client|
          allow(client).to receive(
            :upsert_user_budget_cap_overrides
          ).and_return(cdot_success_response)
        end
      end

      it_behaves_like 'authorizing granular token permissions for GraphQL', :update_subscription_usage_cap do
        let(:user) { admin }
        let(:boundary_object) { :instance }
        let(:mutation) { graphql_mutation(:upsert_user_budget_cap_overrides, mutation_input, 'errors') }
        let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
      end

      it 'returns updated user overrides' do
        post_graphql_mutation(mutation, current_user: current_user)

        mutation_response = graphql_mutation_response(
          :upsert_user_budget_cap_overrides
        )

        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['userOverrides']).to contain_exactly(
          a_hash_including(
            'cap' => 300.0,
            'capEnabled' => true
          ),
          a_hash_including(
            'cap' => 150.0,
            'capEnabled' => false
          )
        )
      end

      it 'passes correct arguments to CDot client' do
        license = create(:license)
        allow(License).to receive_messages(billable_license: license, current: license)

        expect_next_instance_of(
          Gitlab::SubscriptionPortal::SubscriptionUsageClient,
          license_key: license.data,
          namespace_id: nil
        ) do |client|
          expect(client).to receive(
            :upsert_user_budget_cap_overrides
          ).and_return(cdot_success_response)
        end

        post_graphql_mutation(mutation, current_user: current_user)
      end

      context 'when the current license is a trial with an active prior paid license' do
        let(:paid_license) { build(:license, plan: License::PREMIUM_PLAN) }
        let(:trial_license) { build(:license, :ultimate_trial) }

        before do
          allow(License).to receive_messages(billable_license: paid_license, current: trial_license)
        end

        it 'builds the client with the prior paid license key, not the trial key' do
          expect_next_instance_of(
            Gitlab::SubscriptionPortal::SubscriptionUsageClient,
            license_key: paid_license.data,
            namespace_id: nil
          ) do |client|
            expect(client).to receive(
              :upsert_user_budget_cap_overrides
            ).and_return(cdot_success_response)
          end

          post_graphql_mutation(mutation, current_user: current_user)
        end
      end

      context 'when the current license is a trial with no prior paid license (trial-only)' do
        let(:trial_license) { build(:license, :ultimate_trial) }

        before do
          allow(License).to receive_messages(billable_license: nil, current: trial_license)
        end

        it 'builds the client with the current trial license key' do
          expect_next_instance_of(
            Gitlab::SubscriptionPortal::SubscriptionUsageClient,
            license_key: trial_license.data,
            namespace_id: nil
          ) do |client|
            expect(client).to receive(
              :upsert_user_budget_cap_overrides
            ).and_return(cdot_success_response)
          end

          post_graphql_mutation(mutation, current_user: current_user)
        end
      end

      context 'when no license is present' do
        before do
          allow(License).to receive_messages(billable_license: nil, current: nil)
        end

        it 'returns a resource not available error' do
          post_graphql_mutation(mutation, current_user: current_user)

          expect_graphql_errors_to_include(
            /does not exist or you don't have permission/
          )
        end
      end
    end

    context 'when user is not an admin' do
      let(:current_user) { non_owner }

      it_behaves_like 'unauthorized user'
    end
  end

  context 'with negative cap value' do
    let(:current_user) { owner }
    let(:overrides_input) do
      [
        {
          userId: target_user1.to_global_id.to_s,
          cap: -10.0,
          enabled: true
        }
      ]
    end

    it 'returns a validation error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include(/greater than or equal to 0/)
    end
  end

  context 'with both userId and username on the same override' do
    let(:current_user) { owner }
    let(:overrides_input) do
      [
        {
          userId: target_user1.to_global_id.to_s,
          username: target_user1.username,
          cap: 100.0,
          enabled: true
        }
      ]
    end

    it 'returns a validation error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include(/One and only one of \[userId, username\] arguments is required/)
    end
  end

  context 'with neither userId nor username on an override' do
    let(:current_user) { owner }
    let(:overrides_input) { [{ cap: 100.0, enabled: true }] }

    it 'returns a validation error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include(/One and only one of \[userId, username\] arguments is required/)
    end
  end

  context 'with a blank username' do
    let(:current_user) { owner }
    let(:overrides_input) { [{ username: '', cap: 100.0, enabled: true }] }

    it 'returns a validation error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect_graphql_errors_to_include(/can't be blank/)
    end
  end

  context 'when organization ID is given', :saas_gitlab_com_subscriptions do
    let_it_be(:org_subscription) { create(:organization_gitlab_subscription) }
    let_it_be(:organization) { org_subscription.organization }
    let_it_be(:billed_group) { org_subscription.gitlab_subscription.namespace }
    let_it_be(:organization_owner) { create(:user, owner_of: organization) }

    let(:current_user) { organization_owner }
    let(:organization_id) { organization.to_global_id.to_s }
    let(:mutation_input) do
      { organization_id: organization_id, overrides: overrides_input }
    end

    # Target users belong to the Organization but not to the nominated group.
    before_all do
      create(:organization_user, organization: organization, user: target_user1)
      create(:organization_user, organization: organization, user: target_user2)
    end

    context 'when CustomersDot accepts the overrides' do
      let(:client) do
        instance_double(
          Gitlab::SubscriptionPortal::SubscriptionUsageClient,
          upsert_user_budget_cap_overrides: cdot_success_response
        )
      end

      before do
        allow(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to receive(:new).and_return(client)
      end

      it 'sends the nominated group namespace id to CustomersDot' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient)
          .to have_received(:new).with(license_key: nil, namespace_id: billed_group.id)
      end

      it 'returns the overrides' do
        post_graphql_mutation(mutation, current_user: current_user)

        mutation_response = graphql_mutation_response(:upsert_user_budget_cap_overrides)
        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['userOverrides']).to include(
          a_hash_including('cap' => 300.0, 'user' => a_hash_including('username' => target_user1.username))
        )
      end
    end

    context 'when a target user is not part of the organization' do
      let(:overrides_input) do
        [{ userId: non_member_user.to_global_id.to_s, cap: 100.0, enabled: true }]
      end

      it 'returns an error' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect_graphql_errors_to_include(/Users are not part of the organization/)
      end
    end

    context 'when user owns the nominated group but not the organization' do
      let(:current_user) { owner }

      before_all do
        billed_group.add_owner(owner)
      end

      it_behaves_like 'unauthorized user'
    end

    context 'when organization does not exist' do
      let(:organization_id) { "gid://gitlab/Organizations::Organization/#{non_existing_record_id}" }

      it_behaves_like 'unauthorized user'
    end

    # The default Organization can't nominate a billing group, so it never has a billing namespace.
    context 'when organization is the default organization' do
      let_it_be(:default_organization) { create(:organization, :default) } # rubocop:disable Gitlab/RSpec/AvoidCreateDefaultOrganization -- exercising the default organization

      let(:current_user) { create(:user, owner_of: default_organization) }
      let(:organization_id) { default_organization.to_global_id.to_s }

      it_behaves_like 'unauthorized user'
    end

    context 'when organization has no billing namespace' do
      let_it_be(:unbilled_organization) { create(:organization) }

      let(:current_user) { create(:user, owner_of: unbilled_organization) }
      let(:organization_id) { unbilled_organization.to_global_id.to_s }

      it_behaves_like 'unauthorized user'
    end

    context 'when the billing namespace is not a root group' do
      let_it_be(:subgroup_organization) { create(:organization) }
      let_it_be(:parent_group) { create(:group_with_plan, plan: :ultimate_plan, organization: subgroup_organization) }
      let_it_be(:billed_subgroup) { create(:group, parent: parent_group, organization: subgroup_organization) }

      let(:current_user) { create(:user, owner_of: subgroup_organization) }
      let(:organization_id) { subgroup_organization.to_global_id.to_s }

      before_all do
        create(:organization_gitlab_subscription, organization: subgroup_organization,
          gitlab_subscription: create(:gitlab_subscription, namespace: billed_subgroup))
      end

      it 'returns a resource not available error without calling CustomersDot' do
        expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).not_to receive(:new)

        post_graphql_mutation(mutation, current_user: current_user)

        expect_graphql_errors_to_include(/does not exist or you don't have permission/)
      end
    end

    context 'when the billing namespace belongs to another organization' do
      let_it_be(:linked_organization) { create(:organization) }
      let_it_be(:foreign_group) { create(:group_with_plan, plan: :ultimate_plan, organization: create(:organization)) }

      let(:current_user) { create(:user, owner_of: linked_organization) }
      let(:organization_id) { linked_organization.to_global_id.to_s }

      # Target users belong to the linked Organization, so only the foreign group can cause the error.
      before_all do
        create(:organization_gitlab_subscription, organization: linked_organization,
          gitlab_subscription: foreign_group.gitlab_subscription)
        create(:organization_user, organization: linked_organization, user: target_user1)
        create(:organization_user, organization: linked_organization, user: target_user2)
      end

      it 'returns a resource not available error without calling CustomersDot' do
        expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).not_to receive(:new)

        post_graphql_mutation(mutation, current_user: current_user)

        expect_graphql_errors_to_include(/does not exist or you don't have permission/)
      end
    end

    context 'when organization_billing flag is disabled' do
      before do
        stub_feature_flags(organization_billing: false)
      end

      it_behaves_like 'unauthorized user'
    end

    context 'when namespace_path is also given' do
      let(:mutation_input) { super().merge(namespace_path: root_group.full_path) }

      it 'returns a mutually exclusive argument error' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect_graphql_errors_to_include(/Only one of \[namespacePath, organizationId\] arguments is allowed/)
      end
    end
  end
end
