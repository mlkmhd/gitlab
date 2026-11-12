# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Create a custom dashboard', feature_category: :custom_dashboards_foundation do
  include GraphqlHelpers

  let_it_be_with_reload(:user) { create(:user) }
  let_it_be(:organization) { create(:organization) }
  let_it_be_with_refind(:current_organization) { organization }

  let(:valid_config) do
    {
      title: "Quarterly Sales Dashboard",
      description: "Revenue performance tracking",
      panels: [
        {
          title: "Total Revenue",
          visualization: {
            type: 'SingleStat', data: { type: 'glql', query: { glql: 'type = Issue' } }, options: {}
          },
          gridAttributes: { width: 4, height: 2 }
        }
      ]
    }
  end

  let(:variables) do
    {
      organizationId: GitlabSchema.id_from_object(organization).to_s,
      config: valid_config
    }
  end

  let(:mutation) do
    graphql_mutation(
      :create_custom_dashboard,
      variables,
      <<~QL
        dashboard {
          id
          name
          description
          config
          organization {
            id
          }
          createdBy {
            id
          }
        }
        errors
      QL
    )
  end

  let(:mutation_response) { graphql_mutation_response(:create_custom_dashboard) }

  before do
    stub_feature_flags(custom_dashboard_storage: true)
  end

  context 'with granular token authorization' do
    before do
      create(:organization_user, :owner, organization: organization, user: user)
      user.update!(organization: organization)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :create_custom_dashboard do
      let(:boundary_object) { :instance }
      let(:mutation) { graphql_mutation(:create_custom_dashboard, variables, 'errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end

  context 'when user is organization owner' do
    before_all do
      create(:organization_user, :owner, organization: organization, user: user)
    end

    let(:expected_persisted_config) do
      {
        'title' => 'Quarterly Sales Dashboard',
        'description' => 'Revenue performance tracking',
        'version' => '2',
        'panels' => [
          {
            'title' => 'Total Revenue',
            'visualization' => {
              'type' => 'SingleStat',
              'data' => { 'type' => 'glql', 'query' => { 'glql' => 'type = Issue' } },
              'options' => {}
            },
            'gridAttributes' => { 'width' => 4, 'height' => 2 }
          }
        ]
      }
    end

    it 'creates a dashboard with the name and description from the config' do
      expect do
        user.update!(organization: organization)
        post_graphql_mutation(mutation, current_user: user)
      end.to change { Analytics::CustomDashboards::Dashboard.count }.by(1)

      dashboard = Analytics::CustomDashboards::Dashboard.last

      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['dashboard']).to include(
        'name' => 'Quarterly Sales Dashboard',
        'description' => 'Revenue performance tracking'
      )
      expect(dashboard.organization).to eq(organization)
      expect(dashboard.created_by).to eq(user)
      expect(dashboard.config).to eq(expected_persisted_config)
    end

    context 'when organizationId is not the current organization' do
      let_it_be(:other_organization) { create(:organization) }

      let(:variables) { super().merge(organizationId: GitlabSchema.id_from_object(other_organization).to_s) }

      before_all do
        create(:organization_user, :owner, organization: other_organization, user: user)
      end

      it 'returns a resource not available error' do
        expect do
          post_graphql_mutation(mutation, current_user: user)
        end.not_to change { Analytics::CustomDashboards::Dashboard.count }

        expect_graphql_errors_to_include(/Organization not found/i)
      end
    end

    context 'when the deprecated name and description arguments are passed' do
      let(:variables) { super().merge(name: 'Stale Name', description: 'Stale Description') }

      it 'takes the name and description from the config' do
        user.update!(organization: organization)
        post_graphql_mutation(mutation, current_user: user)

        expect(mutation_response['errors']).to be_empty
        expect(Analytics::CustomDashboards::Dashboard.last).to have_attributes(
          name: 'Quarterly Sales Dashboard',
          description: 'Revenue performance tracking'
        )
      end
    end

    context 'when organizationId is not provided' do
      let(:variables) { { config: valid_config } }

      it 'creates a dashboard using the current organization from context' do
        stub_current_organization(organization)

        expect do
          post_graphql_mutation(mutation, current_user: user)
        end.to change { Analytics::CustomDashboards::Dashboard.count }.by(1)

        expect(mutation_response['errors']).to be_empty
        expect(Analytics::CustomDashboards::Dashboard.last.organization).to eq(organization)
      end
    end

    context 'when neither organizationId nor any fallback is available' do
      let(:variables) { { config: valid_config } }

      before do
        allow_next_instance_of(Mutations::Analytics::CustomDashboards::Create) do |instance|
          allow(instance).to receive(:resolve_current_organization).and_return(nil)
        end
      end

      it 'returns a resource not available error' do
        expect do
          post_graphql_mutation(mutation, current_user: user)
        end.not_to change { Analytics::CustomDashboards::Dashboard.count }

        expect_graphql_errors_to_include(/Organization not found/i)
      end
    end

    context 'when dashboard with same name already exists in the same organization and namespace' do
      before do
        create(:dashboard, organization: organization, name: 'Quarterly Sales Dashboard', namespace: nil)
      end

      it 'does not create a duplicate dashboard' do
        expect do
          post_graphql_mutation(mutation, current_user: user)
        end.not_to change { Analytics::CustomDashboards::Dashboard.count }

        expect(mutation_response['errors']).to be_present
        expect(mutation_response['dashboard']).to be_nil
      end
    end

    context 'when dashboard with same name exists in a different namespace' do
      let_it_be(:namespace) { create(:namespace) }

      before do
        create(:dashboard, organization: organization, name: 'Quarterly Sales Dashboard', namespace: namespace)
        variables[:namespaceId] = GitlabSchema.id_from_object(create(:namespace)).to_s
      end

      it 'creates the dashboard successfully' do
        expect do
          post_graphql_mutation(mutation, current_user: user)
        end.to change { Analytics::CustomDashboards::Dashboard.count }.by(1)

        expect(mutation_response['errors']).to be_empty
      end
    end

    context 'when config is missing required fields' do
      let(:variables) { super().merge(config: { title: "No panels dashboard" }) }

      it 'returns validation errors' do
        post_graphql_mutation(mutation, current_user: user)

        expect(mutation_response['dashboard']).to be_nil
        expect(mutation_response['errors']).to be_present
      end
    end

    context 'when feature flag is disabled' do
      before do
        stub_feature_flags(custom_dashboard_storage: false)
      end

      it 'returns an authorization error' do
        expect do
          post_graphql_mutation(mutation, current_user: user)
        end.not_to change { Analytics::CustomDashboards::Dashboard.count }

        expect_graphql_errors_to_include(/does not exist or you don't have permission/i)
      end
    end

    context 'when config includes constraints' do
      let(:variables) { super().merge(config: valid_config.merge(constraints: { data: [] })) }

      it 'returns a validation error' do
        user.update!(organization: organization)

        expect do
          post_graphql_mutation(mutation, current_user: user)
        end.not_to change { Analytics::CustomDashboards::Dashboard.count }

        expect(mutation_response['errors']).to include(/must not include constraints/)
      end
    end

    describe 'write rate limiting', :clean_gitlab_redis_rate_limiting, :freeze_time do
      def consume_rate_limit_for(user, times)
        times.times do
          Gitlab::ApplicationRateLimiter.throttled?(:custom_dashboard_write, scope: { user: user })
        end
      end

      context 'when the user has exhausted the limit' do
        before do
          consume_rate_limit_for(user, 30)
        end

        it 'returns an error and does not create a dashboard' do
          expect do
            post_graphql_mutation(mutation, current_user: user)
          end.not_to change { Analytics::CustomDashboards::Dashboard.count }

          expect(mutation_response['dashboard']).to be_nil
          expect(mutation_response['errors'])
            .to contain_exactly('This endpoint has been requested too many times. Try again later.')
        end

        context 'when the custom_dashboard_write_limits feature flag is disabled' do
          before do
            stub_feature_flags(custom_dashboard_write_limits: false)
          end

          it 'creates the dashboard' do
            expect do
              post_graphql_mutation(mutation, current_user: user)
            end.to change { Analytics::CustomDashboards::Dashboard.count }.by(1)

            expect(mutation_response['errors']).to be_empty
          end
        end

        context 'when the mutation runs without an HTTP request' do
          it 'checks the limit without a request, returns an error and does not create a dashboard' do
            allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
            expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled_request?)
            result = nil

            expect do
              result = GitlabSchema.execute(
                mutation.query, variables: mutation.variables, context: { current_user: user }
              )
            end.not_to change { Analytics::CustomDashboards::Dashboard.count }

            expect(Gitlab::ApplicationRateLimiter)
              .to have_received(:throttled?).with(:custom_dashboard_write, scope: { user: user })
            expect(result.dig('data', 'createCustomDashboard', 'errors'))
              .to contain_exactly('This endpoint has been requested too many times. Try again later.')
          end
        end
      end

      context 'when another user has exhausted the limit' do
        let_it_be(:another_user) { create(:user) }

        before do
          consume_rate_limit_for(another_user, 30)
        end

        it 'creates the dashboard for the current user' do
          expect do
            post_graphql_mutation(mutation, current_user: user)
          end.to change { Analytics::CustomDashboards::Dashboard.count }.by(1)

          expect(mutation_response['errors']).to be_empty
        end
      end

      context 'when the user is not allowed to create dashboards' do
        let_it_be(:regular_member) { create(:user) }

        before_all do
          create(:organization_user, organization: organization, user: regular_member)
        end

        it 'returns the authorization error without consulting the rate limiter' do
          allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
          allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?).and_call_original

          expect do
            post_graphql_mutation(mutation, current_user: regular_member)
          end.not_to change { Analytics::CustomDashboards::Dashboard.count }

          expect_graphql_errors_to_include(/does not exist or you don't have permission/i)
          expect(Gitlab::ApplicationRateLimiter)
            .not_to have_received(:throttled?).with(:custom_dashboard_write, anything)
          expect(Gitlab::ApplicationRateLimiter)
            .not_to have_received(:throttled_request?).with(anything, anything, :custom_dashboard_write, anything)
        end
      end
    end

    context 'when namespace is provided' do
      let_it_be(:namespace) { create(:namespace) }

      before do
        variables[:namespaceId] = GitlabSchema.id_from_object(namespace).to_s
      end

      it 'creates a dashboard scoped to the namespace' do
        expect do
          post_graphql_mutation(mutation, current_user: user)
        end.to change { Analytics::CustomDashboards::Dashboard.count }.by(1)

        dashboard = Analytics::CustomDashboards::Dashboard.last

        expect(mutation_response['errors']).to be_empty
        expect(dashboard.namespace).to eq(namespace)
        expect(dashboard.organization).to eq(organization)
      end
    end

    context 'when namespace_id is invalid' do
      before do
        variables[:namespaceId] = "gid://gitlab/Namespace/#{non_existing_record_id}"
      end

      it 'creates dashboard without namespace association' do
        expect do
          post_graphql_mutation(mutation, current_user: user)
        end.to change { Analytics::CustomDashboards::Dashboard.count }.by(1)

        dashboard = Analytics::CustomDashboards::Dashboard.last

        expect(mutation_response['errors']).to be_empty
        expect(dashboard.namespace).to be_nil
        expect(dashboard.organization).to eq(organization)
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

      let(:variables) do
        {
          organizationId: GitlabSchema.id_from_object(organization).to_s,
          config: {
            title: "Inline Visualization Dashboard",
            panels: [
              {
                title: "GLQL Panel",
                visualization: visualization_config,
                gridAttributes: { width: 4, height: 2 }
              }
            ]
          }
        }
      end

      let(:expected_persisted_config) do
        {
          'title' => 'Inline Visualization Dashboard',
          'version' => '2',
          'panels' => [
            {
              'title' => 'GLQL Panel',
              'visualization' => {
                'version' => 1,
                'type' => 'LineChart',
                'options' => { 'xAxis' => { 'name' => 'Time', 'type' => 'time' } },
                'data' => { 'type' => 'glql', 'query' => { 'glql' => 'type = Issue' } }
              },
              'gridAttributes' => { 'width' => 4, 'height' => 2 }
            }
          ]
        }
      end

      it 'persists the JSON visualization config object' do
        user.update!(organization: organization)

        expect do
          post_graphql_mutation(mutation, current_user: user)
        end.to change { Analytics::CustomDashboards::Dashboard.count }.by(1)

        expect(mutation_response['errors']).to be_empty
        expect(Analytics::CustomDashboards::Dashboard.last.config).to eq(expected_persisted_config)
      end
    end

    context 'when validating panel visualizations' do
      let(:variables) do
        {
          organizationId: GitlabSchema.id_from_object(organization).to_s,
          config: { title: "Visualization Validation Dashboard", panels: panels }
        }
      end

      it_behaves_like 'a custom dashboard mutation validating panel visualizations'
    end

    context 'when config has deeply nested keys' do
      let(:variables) do
        {
          organizationId: GitlabSchema.id_from_object(organization).to_s,
          config: {
            title: "Deep Nesting Dashboard",
            panels: [
              {
                title: "Pipeline Panel",
                visualization: {
                  type: 'SingleStat',
                  data: { type: 'glql', query: { glql: 'type = Issue' } },
                  options: {}
                },
                gridAttributes: { width: 4, height: 2 },
                queryOverrides: {
                  filters: {
                    includeMetrics: ["deployment_frequency"],
                    excludeMetrics: ["lead_time"]
                  },
                  namespace: "my-group"
                }
              }
            ]
          }
        }
      end

      let(:expected_persisted_config) do
        {
          'title' => 'Deep Nesting Dashboard',
          'version' => '2',
          'panels' => [
            {
              'title' => 'Pipeline Panel',
              'visualization' => {
                'type' => 'SingleStat',
                'data' => { 'type' => 'glql', 'query' => { 'glql' => 'type = Issue' } },
                'options' => {}
              },
              'gridAttributes' => { 'width' => 4, 'height' => 2 },
              'queryOverrides' => {
                'filters' => {
                  'includeMetrics' => ['deployment_frequency'],
                  'excludeMetrics' => ['lead_time']
                },
                'namespace' => 'my-group'
              }
            }
          ]
        }
      end

      it 'persists the keys exactly as sent' do
        user.update!(organization: organization)

        expect do
          post_graphql_mutation(mutation, current_user: user)
        end.to change { Analytics::CustomDashboards::Dashboard.count }.by(1)

        expect(mutation_response['errors']).to be_empty
        expect(Analytics::CustomDashboards::Dashboard.last.config).to eq(expected_persisted_config)
      end
    end
  end

  context 'when user is organization member but not owner' do
    let_it_be(:regular_member) { create(:user) }

    before_all do
      create(:organization_user, organization: organization, user: regular_member)
    end

    it 'returns an authorization error' do
      expect do
        post_graphql_mutation(mutation, current_user: regular_member)
      end.not_to change { Analytics::CustomDashboards::Dashboard.count }

      expect_graphql_errors_to_include(/does not exist or you don't have permission/i)
    end
  end

  context 'when user is not organization member' do
    let_it_be(:unauthorized_user) { create(:user) }

    it 'returns an authorization error' do
      expect do
        post_graphql_mutation(mutation, current_user: unauthorized_user)
      end.not_to change { Analytics::CustomDashboards::Dashboard.count }

      expect_graphql_errors_to_include(/does not exist or you don't have permission/i)
    end
  end
end
