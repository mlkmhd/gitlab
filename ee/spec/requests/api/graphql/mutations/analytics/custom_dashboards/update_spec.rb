# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Update a custom dashboard', feature_category: :custom_dashboards_foundation do
  include GraphqlHelpers

  let_it_be(:user, freeze: false) { create(:user) }
  let_it_be(:organization) { create(:organization) }
  let_it_be_with_refind(:current_organization) { organization }
  let_it_be(:namespace, freeze: false) { create(:group, organization: organization) }

  let_it_be(:dashboard) do
    create(
      :dashboard,
      organization: organization,
      namespace: namespace,
      created_by: user,
      name: 'Original Name',
      description: 'Original Description',
      config: {
        version: '2',
        title: 'Original Dashboard',
        panels: []
      }
    )
  end

  let(:new_config) do
    {
      title: 'Updated Dashboard',
      description: 'Updated Description',
      panels: [
        {
          title: 'New Panel',
          visualization: {
            type: 'SingleStat', data: { type: 'glql', query: { glql: 'type = Issue' } }, options: {}
          },
          gridAttributes: { width: 6, height: 3 }
        }
      ]
    }
  end

  let(:expected_persisted_config) do
    {
      'version' => '2',
      'title' => 'Updated Dashboard',
      'description' => 'Updated Description',
      'panels' => [
        {
          'title' => 'New Panel',
          'visualization' => {
            'type' => 'SingleStat',
            'data' => { 'type' => 'glql', 'query' => { 'glql' => 'type = Issue' } },
            'options' => {}
          },
          'gridAttributes' => { 'width' => 6, 'height' => 3 }
        }
      ]
    }
  end

  let(:variables) do
    {
      id: dashboard.to_global_id.to_s,
      config: new_config
    }
  end

  let(:mutation) do
    graphql_mutation(
      :update_custom_dashboard,
      variables,
      <<~QL
        dashboard {
          id
          name
          description
          config
          updatedBy {
            id
            username
          }
        }
        errors
      QL
    )
  end

  let(:mutation_response) { graphql_mutation_response(:update_custom_dashboard) }

  before do
    stub_feature_flags(custom_dashboard_storage: true)
  end

  context 'with granular token authorization' do
    before do
      create(:organization_user, organization: organization, user: user)
      user.update!(organization: organization)
      create(:group_member, :developer, group: namespace, user: user)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_custom_dashboard do
      let(:boundary_object) { :instance }
      let(:mutation) { graphql_mutation(:update_custom_dashboard, variables, 'errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end

  context 'when user can update dashboard' do
    before_all do
      create(:organization_user, organization: organization, user: user)
      user.update!(organization: organization)
      create(:group_member, :developer, group: namespace, user: user)
    end

    it 'updates the dashboard and derives the name and description from the config' do
      expect do
        post_graphql_mutation(mutation, current_user: user)
      end.not_to change { Analytics::CustomDashboards::Dashboard.count }

      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['dashboard']).to include(
        'id' => dashboard.to_global_id.to_s,
        'name' => 'Updated Dashboard',
        'description' => 'Updated Description',
        'config' => expected_persisted_config
      )

      dashboard.reload
      expect(dashboard.name).to eq('Updated Dashboard')
      expect(dashboard.description).to eq('Updated Description')
      expect(dashboard.config).to eq(expected_persisted_config)
      expect(dashboard.updated_by).to eq(user)
    end

    context 'when the deprecated name and description arguments are passed with a config' do
      let(:variables) { super().merge(name: 'Stale Name', description: 'Stale Description') }

      it 'takes the name and description from the config' do
        post_graphql_mutation(mutation, current_user: user)

        expect(mutation_response['errors']).to be_empty
        expect(dashboard.reload).to have_attributes(name: 'Updated Dashboard', description: 'Updated Description')
      end
    end

    it 'updates only provided fields' do
      partial_variables = {
        id: dashboard.to_global_id.to_s,
        name: 'Only Name Changed'
      }

      partial_mutation = graphql_mutation(
        :update_custom_dashboard,
        partial_variables,
        'dashboard { name description } errors'
      )

      post_graphql_mutation(partial_mutation, current_user: user)

      expect(mutation_response['dashboard']).to include(
        'name' => 'Only Name Changed',
        'description' => 'Original Description'
      )

      dashboard.reload
      expect(dashboard.name).to eq('Only Name Changed')
      expect(dashboard.description).to eq('Original Description')
    end

    context 'when the request is scoped to another organization' do
      let_it_be(:other_organization) { create(:organization) }

      before do
        stub_current_organization(other_organization)
      end

      it 'does not find the dashboard' do
        post_graphql_mutation(mutation, current_user: user)

        expect_graphql_errors_to_include(/does not exist or you don't have permission/i)
        expect(dashboard.reload.name).to eq('Original Name')
      end
    end

    context 'when config is missing required fields' do
      let(:variables) do
        {
          id: dashboard.to_global_id.to_s,
          config: { title: 'No panels dashboard' }
        }
      end

      it 'returns validation errors' do
        post_graphql_mutation(mutation, current_user: user)

        expect(mutation_response['dashboard']).to be_nil
        expect(mutation_response['errors']).to be_present
      end
    end

    context 'when config includes constraints' do
      let(:new_config) { { title: 'Updated Dashboard', panels: [], constraints: { data: [] } } }

      it 'returns a validation error and keeps the stored config' do
        expect { post_graphql_mutation(mutation, current_user: user) }.not_to change { dashboard.reload.config }

        expect(mutation_response['errors']).to include(/must not include constraints/)
      end
    end

    context 'when a panel visualization is a JSON config object' do
      let(:visualization_config) do
        {
          version: 1,
          type: 'LineChart',
          options: { xAxis: { name: 'Time', type: 'time' } },
          data: { type: 'glql', query: { glql: 'type = Issue' } }
        }
      end

      let(:new_config) do
        {
          title: 'Updated Dashboard',
          panels: [
            {
              title: 'GLQL Panel',
              visualization: visualization_config,
              gridAttributes: { width: 6, height: 3 }
            }
          ]
        }
      end

      let(:expected_persisted_config) do
        {
          'version' => '2',
          'title' => 'Updated Dashboard',
          'panels' => [
            {
              'title' => 'GLQL Panel',
              'visualization' => {
                'version' => 1,
                'type' => 'LineChart',
                'options' => { 'xAxis' => { 'name' => 'Time', 'type' => 'time' } },
                'data' => { 'type' => 'glql', 'query' => { 'glql' => 'type = Issue' } }
              },
              'gridAttributes' => { 'width' => 6, 'height' => 3 }
            }
          ]
        }
      end

      it 'persists the JSON visualization config object' do
        post_graphql_mutation(mutation, current_user: user)

        expect(mutation_response['errors']).to be_empty
        expect(dashboard.reload.config).to eq(expected_persisted_config)
      end
    end

    context 'when validating panel visualizations' do
      let(:new_config) { { title: 'Updated Dashboard', panels: panels } }

      it_behaves_like 'a custom dashboard mutation validating panel visualizations'
    end

    context 'when feature flag is disabled' do
      before do
        stub_feature_flags(custom_dashboard_storage: false)
      end

      it 'returns an authorization error' do
        post_graphql_mutation(mutation, current_user: user)

        expect_graphql_errors_to_include(/does not exist or you don't have permission/i)
      end
    end

    describe 'write rate limiting', :clean_gitlab_redis_rate_limiting, :freeze_time do
      let(:throttled_message) { 'This endpoint has been requested too many times. Try again later.' }

      def consume_rate_limit_for(user, times)
        times.times do
          Gitlab::ApplicationRateLimiter.throttled?(:custom_dashboard_write, scope: { user: user })
        end
      end

      context 'when the user reaches the limit' do
        before do
          consume_rate_limit_for(user, 29)
        end

        it 'accepts the last update within the limit and rejects the next one' do
          post_graphql_mutation(mutation, current_user: user)

          first_response = graphql_mutation_response(:update_custom_dashboard)
          expect(first_response['errors']).to be_empty
          expect(first_response['dashboard']['name']).to eq('Updated Dashboard')

          expect(Analytics::CustomDashboards::UpdateService).not_to receive(:new)

          post_graphql_mutation(mutation, current_user: user)

          second_response = graphql_mutation_response(:update_custom_dashboard)
          expect(second_response['dashboard']).to be_nil
          expect(second_response['errors']).to contain_exactly(throttled_message)
        end
      end

      context 'when the user has exhausted the limit' do
        before do
          consume_rate_limit_for(user, 30)
        end

        it 'still accepts an update without a config' do
          variables.delete(:config)

          post_graphql_mutation(mutation, current_user: user)

          expect(mutation_response['errors']).to be_empty
          expect(mutation_response['dashboard']['name']).to eq('Original Name')
        end

        it 'logs the throttled request with the user to the auth log' do
          expect(Gitlab::AuthLogger).to receive(:error).with(
            hash_including(
              message: 'Application_Rate_Limiter_Request',
              env: :custom_dashboard_write_request_limit,
              user_id: user.id,
              username: user.username
            )
          )

          post_graphql_mutation(mutation, current_user: user)
        end

        context 'when the custom_dashboard_write_limits feature flag is disabled' do
          before do
            stub_feature_flags(custom_dashboard_write_limits: false)
          end

          it 'updates the dashboard' do
            post_graphql_mutation(mutation, current_user: user)

            expect(mutation_response['errors']).to be_empty
            expect(mutation_response['dashboard']['config']).to eq(expected_persisted_config)
          end
        end
      end

      context 'when another user has exhausted the limit' do
        let_it_be(:another_user) { create(:user) }

        before do
          consume_rate_limit_for(another_user, 30)
        end

        it 'updates the dashboard for the current user' do
          post_graphql_mutation(mutation, current_user: user)

          expect(mutation_response['errors']).to be_empty
          expect(mutation_response['dashboard']['config']).to eq(expected_persisted_config)
        end
      end
    end
  end

  context 'when user is dashboard creator but only has reporter access' do
    let_it_be(:creator) { create(:user, organization: organization) }
    let_it_be(:dashboard_by_creator) do
      create(
        :dashboard,
        organization: organization,
        namespace: namespace,
        created_by: creator
      )
    end

    before_all do
      create(:group_member, :reporter, group: namespace, user: creator)
    end

    it 'allows the creator to update their dashboard' do
      update_mutation = graphql_mutation(
        :update_custom_dashboard,
        { id: dashboard_by_creator.to_global_id.to_s, name: 'Updated by Creator' },
        'dashboard { name } errors'
      )

      post_graphql_mutation(update_mutation, current_user: creator)

      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['dashboard']['name']).to eq('Updated by Creator')
    end
  end

  context 'when user is organization member but lacks namespace access' do
    let_it_be(:unauthorized_user) { create(:user, organization: organization) }

    it 'returns an authorization error' do
      post_graphql_mutation(mutation, current_user: unauthorized_user)

      expect_graphql_errors_to_include(/does not exist or you don't have permission/i)
    end
  end

  context 'when user is not organization member' do
    let_it_be(:unauthorized_user) { create(:user) }

    it 'returns an authorization error' do
      post_graphql_mutation(mutation, current_user: unauthorized_user)

      expect_graphql_errors_to_include(/does not exist or you don't have permission/i)
    end
  end

  context 'when dashboard does not exist' do
    let(:variables) do
      {
        id: "gid://gitlab/Analytics::CustomDashboards::Dashboard/#{non_existing_record_id}",
        name: 'Updated Name'
      }
    end

    it 'returns an error' do
      post_graphql_mutation(mutation, current_user: user)

      expect_graphql_errors_to_include(/does not exist or you don't have permission/i)
    end
  end
end
