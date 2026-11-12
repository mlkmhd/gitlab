# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::CustomDashboards::UpdateService, feature_category: :custom_dashboards_foundation do
  let_it_be_with_reload(:user) { create(:user) }
  let_it_be(:organization) { create(:organization) }
  let_it_be(:namespace) { create(:group, organization: organization) }

  let_it_be_with_reload(:dashboard) do
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

  let(:current_user) { user }

  let(:new_config) do
    {
      version: '2',
      title: 'Updated Dashboard',
      description: 'Updated Description',
      panels: [
        {
          title: 'New Panel',
          visualization: { type: 'SingleStat', data: { type: 'glql', query: { glql: 'type = Issue' } }, options: {} },
          gridAttributes: { width: 6, height: 3 }
        }
      ]
    }
  end

  let(:params) { { config: new_config } }

  subject(:execute) do
    described_class.new(current_user: current_user, dashboard: dashboard, params: params).execute
  end

  before do
    stub_licensed_features(product_analytics: true)
    stub_feature_flags(custom_dashboard_storage: true)
  end

  describe '#execute' do
    context 'when user can update dashboard' do
      before_all do
        create(:organization_user, organization: organization, user: user)
        user.update!(organization: organization)
        create(:group_member, :developer, group: namespace, user: user)
      end

      context 'with valid params' do
        it 'updates the dashboard and returns a success response' do
          expect { execute }.not_to change { Analytics::CustomDashboards::Dashboard.count }

          expect(execute).to be_success

          updated_dashboard = execute.payload[:dashboard]
          expect(updated_dashboard.name).to eq('Updated Dashboard')
          expect(updated_dashboard.description).to eq('Updated Description')
          expect(updated_dashboard.config).to eq(new_config.deep_stringify_keys)
          expect(updated_dashboard.updated_by).to eq(user)
        end

        it 'updates only provided fields' do
          partial_params = { name: 'Only Name Changed' }

          result = described_class.new(
            current_user: current_user,
            dashboard: dashboard,
            params: partial_params
          ).execute

          expect(result).to be_success
          expect(result.payload[:dashboard].name).to eq('Only Name Changed')
          expect(result.payload[:dashboard].description).to eq('Original Description')
        end

        context 'when name and description params disagree with the config' do
          let(:params) { super().merge(name: 'Stale Name', description: 'Stale Description') }

          it 'takes the name and description from the config' do
            expect(execute.payload[:dashboard]).to have_attributes(
              name: 'Updated Dashboard',
              description: 'Updated Description'
            )
          end
        end

        context 'when the config has no description' do
          let(:new_config) { super().except(:description) }

          it 'clears the description' do
            expect(execute.payload[:dashboard].description).to eq('')
          end
        end

        it 'tracks the user who updated the dashboard' do
          execute

          expect(dashboard.reload.updated_by).to eq(user)
        end
      end

      context 'when the dashboard holds the maximum number of versions' do
        before do
          stub_const("#{described_class}::MAX_VERSIONS_PER_DASHBOARD", 2)
          create(:dashboard_version, dashboard: dashboard, version_number: 1, updated_by: user)
          create(:dashboard_version, dashboard: dashboard, version_number: 2, updated_by: user)
        end

        it 'records the new version and prunes the oldest one' do
          expect(execute).to be_success

          expect(dashboard.dashboard_versions.pluck(:version_number)).to contain_exactly(2, 3)
        end

        it 'does not prune when the config is unchanged' do
          create(:dashboard_version, dashboard: dashboard, version_number: 3, updated_by: user)

          result = described_class.new(
            current_user: current_user, dashboard: dashboard, params: { name: 'Only Name Changed' }
          ).execute

          expect(result).to be_success
          expect(dashboard.dashboard_versions.pluck(:version_number)).to contain_exactly(1, 2, 3)
        end

        it 'prunes at most one batch per update' do
          stub_const("#{described_class}::VERSION_PRUNE_BATCH_SIZE", 1)
          create(:dashboard_version, dashboard: dashboard, version_number: 3, updated_by: user)

          expect(execute).to be_success

          expect(dashboard.dashboard_versions.pluck(:version_number)).to contain_exactly(2, 3, 4)
        end

        context 'when the custom_dashboard_write_limits feature flag is disabled' do
          before do
            stub_feature_flags(custom_dashboard_write_limits: false)
          end

          it 'keeps every version' do
            expect(execute).to be_success

            expect(dashboard.dashboard_versions.pluck(:version_number)).to contain_exactly(1, 2, 3)
          end
        end

        context 'when the prune fails' do
          before do
            allow(Analytics::CustomDashboards::DashboardVersion).to receive(:oldest_up_to_version)
              .and_raise(ActiveRecord::QueryCanceled, 'canceling statement due to statement timeout')
            allow(Gitlab::ErrorTracking).to receive(:track_exception)
          end

          it 'keeps the saved update and version, tracks the error and still succeeds' do
            expect(execute).to be_success

            expect(dashboard.reload.config).to eq(new_config.deep_stringify_keys)
            expect(dashboard.dashboard_versions.pluck(:version_number)).to contain_exactly(1, 2, 3)
            expect(Gitlab::ErrorTracking).to have_received(:track_exception)
              .with(an_instance_of(ActiveRecord::QueryCanceled), dashboard_id: dashboard.id)
          end
        end
      end

      context 'when the update brings the dashboard exactly to the maximum number of versions' do
        before do
          stub_const("#{described_class}::MAX_VERSIONS_PER_DASHBOARD", 2)
          create(:dashboard_version, dashboard: dashboard, version_number: 1, updated_by: user)
        end

        it 'keeps every version and issues no delete' do
          recorder = ActiveRecord::QueryRecorder.new { expect(execute).to be_success }

          expect(recorder.log).not_to include(a_string_matching(/DELETE FROM "custom_dashboard_versions"/))
          expect(dashboard.dashboard_versions.pluck(:version_number)).to contain_exactly(1, 2)
        end
      end

      context 'when the dashboard is within the maximum number of versions' do
        it 'issues no delete' do
          recorder = ActiveRecord::QueryRecorder.new { expect(execute).to be_success }

          expect(recorder.log).not_to include(a_string_matching(/DELETE FROM "custom_dashboard_versions"/))
          expect(dashboard.dashboard_versions.pluck(:version_number)).to contain_exactly(1)
        end
      end

      context 'with invalid params' do
        context 'when name is blank' do
          let(:params) { { name: '' } }

          it 'does not update the dashboard and returns an error response' do
            expect { execute }.not_to change { dashboard.reload.name }

            expect(execute).to be_error
            expect(execute.message).to include("Name can't be blank")
          end
        end

        context 'when config is invalid' do
          let(:params) { super().merge(config: { invalid: 'schema' }) }

          it 'does not update the dashboard and returns an error response' do
            expect { execute }.not_to change { dashboard.reload.config }

            expect(execute).to be_error
          end
        end

        context 'when config is not a hash' do
          let(:params) { super().merge(config: 'not a hash') }

          it 'does not update the dashboard and returns an error response' do
            expect { execute }.not_to change { dashboard.reload.config }

            expect(execute).to be_error
            expect(execute.message).to include('Config must be a JSON object')
          end
        end
      end
    end

    context 'when user is dashboard creator but only has reporter access' do
      let_it_be(:creator) { create(:user, organization: organization) }
      let_it_be_with_reload(:dashboard_by_creator) do
        create(
          :dashboard,
          organization: organization,
          namespace: namespace,
          created_by: creator,
          name: 'Creator Dashboard'
        )
      end

      let(:current_user) { creator }

      before_all do
        create(:group_member, :reporter, group: namespace, user: creator)
      end

      it 'allows the creator to update their dashboard' do
        result = described_class.new(
          current_user: creator,
          dashboard: dashboard_by_creator,
          params: { name: 'Updated by Creator' }
        ).execute

        expect(result).to be_success
        expect(result.payload[:dashboard].name).to eq('Updated by Creator')
      end
    end

    context 'when user cannot update dashboard' do
      let_it_be(:unauthorized_user) { create(:user, organization: organization) }
      let(:current_user) { unauthorized_user }

      before_all do
        create(:group_member, :reporter, group: namespace, user: unauthorized_user)
      end

      it 'returns an authorization error' do
        expect { execute }.not_to change { dashboard.reload.updated_at }

        expect(execute).to be_error
        expect(execute.message).to eq('You are not authorized to update this dashboard')
      end
    end

    context 'when dashboard is nil' do
      let(:dashboard) { nil }

      it 'returns an error' do
        expect(execute).to be_error
        expect(execute.message).to eq('Dashboard not found')
      end
    end

    context 'when dashboard is a system dashboard' do
      let(:dashboard) do
        Analytics::CustomDashboards::SystemDashboard.new(
          slug: 'gitlab_duo',
          config: { 'title' => 'Test', 'version' => '2', 'panels' => [] }
        )
      end

      it 'returns an authorization error' do
        expect(execute).to be_error
        expect(execute.message).to eq('You are not authorized to update this dashboard')
      end
    end
  end
end
