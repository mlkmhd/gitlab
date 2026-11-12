# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::Settings::SecureController, feature_category: :dependency_firewall do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }

  let(:licensed_feature_available) { true }

  before do
    stub_licensed_features(dependency_firewall: licensed_feature_available)

    sign_in(user)
  end

  shared_examples 'renders 404' do
    it 'renders 404' do
      subject

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  describe 'GET /groups/:group_id/-/settings/secure' do
    subject(:request) { get group_settings_secure_path(group) }

    context 'when the AI Governance setting is available' do
      before_all do
        group.add_owner(user)
      end

      it 'renders the page with the AI Governance section', :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to include('js-ai-governance-settings')
      end

      context 'when the group is a subgroup' do
        let_it_be(:subgroup) { create(:group, parent: group) }

        subject(:request) { get group_settings_secure_path(subgroup) }

        it 'renders the page with the AI Governance section', :aggregate_failures do
          request

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.body).to include('js-ai-governance-settings')
        end
      end
    end

    context 'when on GitLab.com', :saas_dependency_firewall do
      # Isolate the other sections' availability from the AI Governance section.
      before do
        stub_feature_flags(ai_governance_settings_page: false)
      end

      context 'and the user is a group owner' do
        before_all do
          group.add_owner(user)
        end

        it 'renders the page', :aggregate_failures do
          request

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.body).to include('js-dependency-firewall-settings')
        end

        context 'when the dependency_firewall licensed feature is unavailable' do
          let(:licensed_feature_available) { false }

          it_behaves_like 'renders 404'
        end

        context 'when the dependency_firewall_phase1 feature flag is disabled' do
          before do
            stub_feature_flags(dependency_firewall_phase1: false)
          end

          it_behaves_like 'renders 404'
        end

        context 'when the group is a subgroup' do
          let_it_be(:subgroup) { create(:group, parent: group) }

          subject(:request) { get group_settings_secure_path(subgroup) }

          before_all do
            subgroup.add_owner(user)
          end

          it_behaves_like 'renders 404'
        end
      end

      context 'and the user is not a group admin' do
        before_all do
          group.add_maintainer(user)
        end

        it_behaves_like 'renders 404'
      end
    end

    context 'when not on GitLab.com' do
      before_all do
        group.add_owner(user)
      end

      before do
        stub_feature_flags(ai_governance_settings_page: false)
      end

      it_behaves_like 'renders 404'

      context 'when the secrets manager setting is available' do
        before do
          allow(::SecretsManagement::Availability).to receive(:for_group?).and_return(true)
        end

        # A self-managed group has nothing actionable
        # here until the secrets manager is provisioned (the enable toggle
        # lives in the admin settings), so the page hides with the sidebar.
        it_behaves_like 'renders 404'

        context 'when the group has provisioned the secrets manager' do
          before do
            create(:group_secrets_manager, :active, group: group)
          end

          it 'renders the page with the secrets manager section', :aggregate_failures do
            request

            expect(response).to have_gitlab_http_status(:ok)
            expect(response.body).to include('js-group-secrets-manager-settings')
          end
        end
      end
    end
  end

  describe 'PATCH /groups/:group_id/-/settings/secure', :saas_dependency_firewall do
    subject(:request) do
      patch group_settings_secure_path(group), params: { group: { dependency_firewall_enabled: true } }
    end

    context 'and the user is a group owner' do
      before_all do
        group.add_owner(user)
      end

      it 'updates the setting and redirects back to the secure settings page' do
        request

        expect(group.namespace_settings.reload.dependency_firewall_enabled).to be(true)
        expect(response).to redirect_to(
          group_settings_secure_path(group, anchor: 'js-dependency-firewall-settings')
        )
      end

      context 'when the dependency_firewall licensed feature is unavailable' do
        let(:licensed_feature_available) { false }

        it_behaves_like 'renders 404'
      end

      context 'when only the secrets manager setting is available' do
        before do
          allow(::Security::DependencyFirewall::Availability).to receive(:namespace_configurable?).and_return(false)
          allow(::SecretsManagement::Availability).to receive(:for_group?).and_return(true)
        end

        it 'does not update the setting and renders 404', :aggregate_failures do
          request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(group.namespace_settings.reload.dependency_firewall_enabled).not_to be(true)
        end
      end

      context 'when only the AI Governance setting is available' do
        before do
          allow(::Security::DependencyFirewall::Availability).to receive(:namespace_configurable?).and_return(false)
        end

        it 'does not update the setting and renders 404', :aggregate_failures do
          request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(group.namespace_settings.reload.dependency_firewall_enabled).not_to be(true)
        end
      end
    end

    context 'and the user is not a group admin' do
      before_all do
        group.add_maintainer(user)
      end

      it_behaves_like 'renders 404'
    end
  end

  describe 'PATCH /groups/:group_id/-/settings/secure/ai_governance', feature_category: :ai_governance do
    let(:target_group) { group }
    let(:group_params) { { ai_governance_enabled: true, lock_ai_governance_enabled: true } }

    subject(:request) do
      patch ai_governance_group_settings_secure_path(target_group), params: { group: group_params }, as: :json
    end

    context 'when the user is a group owner' do
      before_all do
        group.add_owner(user)
      end

      it 'updates the setting and the lock', :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(group.namespace_settings.reload).to have_attributes(
          ai_governance_enabled: true,
          lock_ai_governance_enabled: true
        )
      end

      it 'queues the cascade job' do
        expect(::Namespaces::CascadeDuoSettingsWorker)
          .to receive(:perform_async).with(group.id, ['ai_governance_enabled'], user.id, {})

        request
      end

      context 'when updating the AI audit events storage setting' do
        let(:group_params) { { ai_audit_events_storage_enabled: true } }

        it 'updates the setting', :aggregate_failures do
          request

          expect(response).to have_gitlab_http_status(:ok)
          expect(group.namespace_settings.reload.ai_audit_events_storage_enabled).to be(true)
        end
      end

      context 'when locking the AI audit events storage setting' do
        let(:group_params) { { ai_audit_events_storage_enabled: true, lock_ai_audit_events_storage_enabled: true } }

        it 'saves the lock', :aggregate_failures do
          request

          expect(response).to have_gitlab_http_status(:ok)
          expect(group.namespace_settings.reload).to have_attributes(
            ai_audit_events_storage_enabled: true,
            lock_ai_audit_events_storage_enabled: true
          )
        end
      end

      context 'when the group is a subgroup' do
        let_it_be(:subgroup) { create(:group, parent: group) }

        let(:target_group) { subgroup }
        let(:group_params) { { ai_governance_enabled: false } }

        before do
          group.reload.namespace_settings.update!(ai_governance_enabled: true)
        end

        it 'overrides the inherited value', :aggregate_failures do
          request

          expect(response).to have_gitlab_http_status(:ok)
          expect(subgroup.reload.namespace_settings.ai_governance_enabled).to be(false)
        end

        context 'when an ancestor locks the setting' do
          before do
            group.reload.namespace_settings.update!(lock_ai_governance_enabled: true)
          end

          it 'does not change the value', :aggregate_failures do
            request

            expect(response).to have_gitlab_http_status(:unprocessable_entity)
            expect(json_response['message']).to include(
              s_('CascadingSettings|cannot be changed because it is locked by an ancestor')
            )
            expect(subgroup.reload.namespace_settings.ai_governance_enabled).to be(true)
          end
        end
      end

      context 'when the ai_governance_settings_page feature flag is disabled' do
        before do
          stub_feature_flags(ai_governance_settings_page: false)
        end

        it_behaves_like 'renders 404'

        context 'when another Secure setting keeps the page available', :saas_dependency_firewall do
          it 'does not update the setting and renders 404', :aggregate_failures do
            expect(::Groups::UpdateService).not_to receive(:new)

            request

            expect(response).to have_gitlab_http_status(:not_found)
          end
        end
      end
    end

    context 'when the user is a maintainer' do
      before_all do
        group.add_maintainer(user)
      end

      it 'does not update the setting and renders 404', :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:not_found)
        expect(group.reload.namespace_settings.ai_governance_enabled).not_to be(true)
      end
    end
  end
end
