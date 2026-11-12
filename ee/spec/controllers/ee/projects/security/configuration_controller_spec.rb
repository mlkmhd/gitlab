# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::Security::ConfigurationController, feature_category: :security_testing_configuration do
  let_it_be(:project) { create(:project, :public) }
  let_it_be(:user) { create(:user) }

  before do
    allow(controller).to receive(:ensure_security_and_compliance_enabled!)
    allow(controller).to receive(:ensure_security_dashboard_feature_enabled!)
    allow(controller).to receive(:authorize_read_security_dashboard!)
    allow(controller).to receive(:add_gon_variables)

    sign_in(user)
  end

  describe 'GET show' do
    context 'when user has developer access' do
      before_all do
        project.add_developer(user)
      end

      it 'pushes security_attributes licensed feature to the frontend' do
        allow(controller).to receive(:push_licensed_feature)

        get :show, params: { namespace_id: project.namespace, project_id: project }

        expect(controller).to have_received(:push_licensed_feature)
          .with(:security_attributes, project.root_ancestor)
      end

      it 'pushes the triage and remediation profiles UI feature flag to the frontend' do
        allow(controller).to receive(:push_frontend_feature_flag)

        get :show, params: { namespace_id: project.namespace, project_id: project }

        expect(controller).to have_received(:push_frontend_feature_flag)
          .with(:triage_and_remediation_profiles_ui, project.root_ancestor)
      end
    end

    describe 'security nav indicator' do
      let(:maintainer) { create(:user, maintainer_of: project) }
      let(:developer) { create(:user, developer_of: project) }
      let(:callout_feature_name) { 'security_configuration_nav_indicator' }

      before do
        stub_licensed_features(security_scan_profiles: true)
      end

      def show
        get :show, params: { namespace_id: project.namespace, project_id: project }
      end

      context 'on a date before the indicator expires' do
        around do |example|
          travel_to(::Security::NavIndicator::EXPIRES_ON - 1.day) { example.run }
        end

        it 'dismisses the page callout for a user who can apply security scan profiles' do
          sign_in(maintainer)

          expect { show }.to change { Users::Callout.where(user: maintainer, feature_name: callout_feature_name).count }
            .from(0).to(1)
        end

        it 'does not dismiss the callout when the feature flag is disabled' do
          stub_feature_flags(security_nav_indicator: false)
          sign_in(maintainer)

          expect { show }.not_to change { Users::Callout.count }
          expect(response).to have_gitlab_http_status(:ok)
        end

        it 'does not dismiss the callout for a JSON request' do
          sign_in(maintainer)

          expect { get :show, params: { namespace_id: project.namespace, project_id: project }, format: :json }
            .not_to change { Users::Callout.count }
          expect(response).to have_gitlab_http_status(:ok)
        end

        it 'does not dismiss the callout for a user who cannot apply security scan profiles' do
          sign_in(developer)

          expect { show }.not_to change { Users::Callout.count }
          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when the indicator has expired' do
        around do |example|
          travel_to(::Security::NavIndicator::EXPIRES_ON + 1.day) { example.run }
        end

        it 'does not dismiss the callout' do
          sign_in(maintainer)

          expect { show }.not_to change { Users::Callout.count }
          expect(response).to have_gitlab_http_status(:ok)
        end
      end
    end
  end
end
