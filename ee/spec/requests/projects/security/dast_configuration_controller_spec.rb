# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::Security::DastConfigurationController,
  :clean_gitlab_redis_rate_limiting, feature_category: :dynamic_application_security_testing do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user) }

  describe 'GET #show' do
    before do
      stub_licensed_features(security_dashboard: true)
      login_as(user)
    end

    include_context '"Security and compliance" permissions' do
      let(:valid_request) { get project_security_configuration_dast_path(project) }

      before_request do
        project.add_developer(user)
      end
    end

    context 'feature available' do
      context 'user authorized' do
        before do
          project.add_developer(user)
        end

        it 'can access page' do
          get project_security_configuration_dast_path(project)

          expect(response).to have_gitlab_http_status(:ok)
        end

        it_behaves_like 'rate limited endpoint', rate_limit_key: :dast_configuration_show, use_second_scope: false do
          let(:current_user) { user }

          def request
            get project_security_configuration_dast_path(project)
          end
        end

        context 'when the user is rate limited' do
          before do
            allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?)
              .with(anything, user, :dast_configuration_show, scope: { user: user })
              .and_return(true)
          end

          it 'returns too many requests without reading the CI config' do
            expect(AppSec::Dast::ScanConfigs::FetchService).not_to receive(:new)

            get project_security_configuration_dast_path(project)

            expect(response).to have_gitlab_http_status(:too_many_requests)
          end

          context 'when the dast_configuration_rate_limit feature flag is enabled only for the user' do
            before do
              stub_feature_flags(dast_configuration_rate_limit: user)
            end

            it 'returns too many requests' do
              get project_security_configuration_dast_path(project)

              expect(response).to have_gitlab_http_status(:too_many_requests)
            end
          end

          context 'when the dast_configuration_rate_limit feature flag is disabled' do
            before do
              stub_feature_flags(dast_configuration_rate_limit: false)
            end

            it 'can access page' do
              get project_security_configuration_dast_path(project)

              expect(response).to have_gitlab_http_status(:ok)
            end
          end
        end
      end

      context 'user not authorized' do
        before do
          project.add_guest(user)
        end

        it 'sees a 404 error' do
          get project_security_configuration_dast_path(project)

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end
    end

    context 'feature not available' do
      context "license doesn't support the feature" do
        before do
          stub_licensed_features(security_dashboard: false)
          project.add_developer(user)
        end

        it 'sees a 404 error' do
          get project_security_configuration_dast_path(project)

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end
  end
end
