# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::Organizations::HooksController, :without_current_organization, feature_category: :webhooks do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:other_organization) { create(:organization) }
  let_it_be(:admin) { create(:admin) }
  let_it_be(:organization_owner) { create(:user, :organization_owner, organization: organization) }
  let_it_be(:regular_user) { create(:user) }

  shared_examples 'a request gated by the org_admin_hooks feature flag' do
    before do
      sign_in(organization_owner)
      stub_feature_flags(org_admin_hooks: false)
    end

    it 'returns 404' do
      request

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  shared_examples 'a request blocked on GitLab.com' do
    before do
      sign_in(organization_owner)
    end

    it 'returns 404', :saas do
      request

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  shared_examples 'a request denied without the ability' do |ability|
    before do
      sign_in(organization_owner)
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(organization_owner, ability, anything).and_return(false)
    end

    it 'returns 404' do
      request

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  describe 'requests for the default organization' do
    let_it_be(:default_organization) { create(:organization, :default) } # rubocop:disable Gitlab/RSpec/AvoidCreateDefaultOrganization -- Default organization org-level hooks are only managed by instance admin in /admin/hooks
    let_it_be(:default_organization_owner) do
      create(:user, :organization_owner, organization: default_organization)
    end

    let_it_be(:hook) { create(:system_hook, organization: default_organization) }

    context 'when user is an owner of the default organization' do
      before do
        sign_in(default_organization_owner)
      end

      it 'returns 404 for the index' do
        get organization_admin_settings_hooks_path(default_organization)

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'does not create a hook and returns 404', :aggregate_failures do
        expect do
          post organization_admin_settings_hooks_path(default_organization),
            params: { hook: { url: 'http://example.com/hook' } }
        end.not_to change { default_organization.system_hooks.count }

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when user is an instance admin', :enable_admin_mode do
      before do
        sign_in(admin)
      end

      it 'returns 404 for the index' do
        get organization_admin_settings_hooks_path(default_organization)

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'returns 404 for the edit page' do
        get edit_organization_admin_settings_hook_path(default_organization, hook)

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'returns 404 for the test action and does not execute the hook', :aggregate_failures do
        expect(TestHooks::SystemService).not_to receive(:new)

        post test_organization_admin_settings_hook_path(default_organization, hook, trigger: 'push_events')

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'GET /o/:organization_path/admin/settings/hooks' do
    subject(:request) { get organization_admin_settings_hooks_path(organization) }

    let(:other_organization_request) { get organization_admin_settings_hooks_path(other_organization) }

    it_behaves_like 'an organization admin area request'
    it_behaves_like 'a request gated by the org_admin_hooks feature flag'
    it_behaves_like 'a request blocked on GitLab.com'
    it_behaves_like 'a request denied without the ability', :read_webhook

    context 'when the org_admin_hooks flag is enabled for specific organizations' do
      before do
        sign_in(organization_owner)
      end

      context 'when the flag is enabled only for another organization' do
        before do
          stub_feature_flags(org_admin_hooks: other_organization)
        end

        it 'returns 404' do
          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when the flag is enabled only for this organization' do
        before do
          stub_feature_flags(org_admin_hooks: organization)
        end

        it 'renders the page' do
          request

          expect(response).to have_gitlab_http_status(:ok)
        end
      end
    end

    context 'when user is an organization owner' do
      before do
        sign_in(organization_owner)
      end

      it 'renders the webhooks page with organization-scoped paths', :aggregate_failures do
        hook = create(:system_hook, organization: organization)

        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to include(organization_admin_settings_hooks_path(organization))
        expect(response.body).to include(edit_organization_admin_settings_hook_path(organization, hook))
        expect(response.body).not_to include('/admin/hooks')
      end

      it_behaves_like 'system hook listing scoped to the organization' do
        def listed_system_hook_ids
          request

          response.body.scan(%r{/admin/settings/hooks/(\d+)/edit}).flatten.map(&:to_i)
        end
      end

      it 'does not introduce N+1 queries when listing hooks' do
        create(:system_hook, organization: organization)
        get organization_admin_settings_hooks_path(organization)

        control = ActiveRecord::QueryRecorder.new { get organization_admin_settings_hooks_path(organization) }

        create_list(:system_hook, 2, organization: organization)

        expect { get organization_admin_settings_hooks_path(organization) }
          .to issue_same_number_of_queries_as(control).ignoring_cached_queries
      end
    end
  end

  describe 'POST /o/:organization_path/admin/settings/hooks' do
    subject(:request) do
      post organization_admin_settings_hooks_path(organization), params: { hook: { url: 'http://example.com/hook' } }
    end

    it_behaves_like 'a request gated by the org_admin_hooks feature flag'
    it_behaves_like 'a request blocked on GitLab.com'
    it_behaves_like 'a request denied without the ability', :create_webhook

    context 'when user is an organization owner' do
      before do
        sign_in(organization_owner)
      end

      it 'creates a hook in the organization and redirects to the index', :aggregate_failures do
        expect { request }.to change { organization.system_hooks.count }.by(1)

        expect(organization.system_hooks.last.url).to eq('http://example.com/hook')
        expect(response).to redirect_to(organization_admin_settings_hooks_path(organization))
      end

      it 'does not create a hook in another organization' do
        expect { request }.not_to change { other_organization.system_hooks.count }
      end

      context 'when the create rate limit is reached' do
        before do
          allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?)
            .with(anything, organization_owner, :system_hooks_create, scope: { user: organization_owner })
            .and_return(true)
        end

        it 'does not create a hook and redirects back with an alert', :aggregate_failures do
          expect { request }.not_to change { SystemHook.count }

          expect(response).to have_gitlab_http_status(:redirect)
          expect(flash[:alert]).to eq(Gitlab::ApplicationRateLimiter.throttled_error_message)
        end
      end
    end

    context 'when user has no access to the organization admin area' do
      before do
        sign_in(regular_user)
      end

      it 'does not create a hook and returns 404', :aggregate_failures do
        expect { request }.not_to change { SystemHook.count }

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'GET /o/:organization_path/admin/settings/hooks/:id/edit' do
    let_it_be(:hook) { create(:system_hook, organization: organization) }
    let(:other_organization_request) { get edit_organization_admin_settings_hook_path(other_organization, hook) }

    subject(:request) { get edit_organization_admin_settings_hook_path(organization, hook) }

    it_behaves_like 'a request gated by the org_admin_hooks feature flag'
    it_behaves_like 'a request blocked on GitLab.com'
    it_behaves_like 'a request denied without the ability', :update_webhook

    context 'when user is an organization owner' do
      before do
        sign_in(organization_owner)
      end

      it 'renders the edit form with organization-scoped paths', :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to include(organization_admin_settings_hook_path(organization, hook))
        expect(response.body).not_to include('/admin/hooks')
      end

      it_behaves_like 'system hook lookup scoped to the organization' do
        def request_system_hook(hook)
          get edit_organization_admin_settings_hook_path(organization, hook)
        end
      end
    end

    context 'when user is an instance admin', :enable_admin_mode do
      before do
        sign_in(admin)
      end

      it 'renders the page' do
        request

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when the hook is requested through another organization' do
      before do
        sign_in(organization_owner)
      end

      it 'returns 404' do
        other_organization_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'PUT /o/:organization_path/admin/settings/hooks/:id' do
    let_it_be(:hook) { create(:system_hook, organization: organization) }

    let(:params) { { hook: { url: 'http://example.com/changed' } } }

    subject(:request) { put organization_admin_settings_hook_path(organization, hook), params: params }

    it_behaves_like 'a request gated by the org_admin_hooks feature flag'
    it_behaves_like 'a request blocked on GitLab.com'
    it_behaves_like 'a request denied without the ability', :update_webhook

    context 'when user is an organization owner' do
      before do
        sign_in(organization_owner)
      end

      it 'updates the hook and redirects to the edit page', :aggregate_failures do
        request

        expect(hook.reload.url).to eq('http://example.com/changed')
        expect(response).to redirect_to(edit_organization_admin_settings_hook_path(organization, hook))
      end

      it_behaves_like 'system hook lookup scoped to the organization' do
        def request_system_hook(hook)
          put organization_admin_settings_hook_path(organization, hook), params: params
        end
      end
    end
  end

  describe 'DELETE /o/:organization_path/admin/settings/hooks/:id' do
    let_it_be_with_reload(:hook) { create(:system_hook, organization: organization) }

    subject(:request) { delete organization_admin_settings_hook_path(organization, hook) }

    it_behaves_like 'a request gated by the org_admin_hooks feature flag'
    it_behaves_like 'a request blocked on GitLab.com'
    it_behaves_like 'a request denied without the ability', :delete_webhook

    context 'when user is an organization owner' do
      before do
        sign_in(organization_owner)
      end

      it 'deletes the hook and redirects to the index', :aggregate_failures do
        expect { request }.to change { SystemHook.exists?(hook.id) }.from(true).to(false)

        expect(response).to redirect_to(organization_admin_settings_hooks_path(organization))
      end

      it_behaves_like 'system hook lookup scoped to the organization' do
        def request_system_hook(hook)
          delete organization_admin_settings_hook_path(organization, hook)
        end
      end
    end
  end

  describe 'POST /o/:organization_path/admin/settings/hooks/:id/test' do
    let_it_be(:hook) { create(:system_hook, organization: organization) }

    subject(:request) { post test_organization_admin_settings_hook_path(organization, hook, trigger: 'push_events') }

    it_behaves_like 'a request gated by the org_admin_hooks feature flag'
    it_behaves_like 'a request blocked on GitLab.com'
    it_behaves_like 'a request denied without the ability', :test_webhook

    context 'when user is an organization owner' do
      include StubRequests

      before do
        sign_in(organization_owner)
      end

      def stub_hook_endpoint(hook)
        stub_full_request(hook.interpolated_url, method: :post).to_return(status: 200)
      end

      it 'executes the hook and redirects to the index with a notice', :aggregate_failures do
        endpoint = stub_hook_endpoint(hook)

        request

        expect(endpoint).to have_been_requested.once
        expect(response).to redirect_to(organization_admin_settings_hooks_path(organization))
        expect(flash[:notice]).to eq('Hook executed successfully: HTTP 200')
      end

      context 'when the hook is permanently disabled' do
        let_it_be_with_reload(:disabled_hook) do
          create(:system_hook, organization: organization,
            recent_failures: WebHooks::AutoDisabling::PERMANENTLY_DISABLED_FAILURE_THRESHOLD + 1)
        end

        it 're-enables the hook' do
          stub_hook_endpoint(disabled_hook)
          path = test_organization_admin_settings_hook_path(organization, disabled_hook, trigger: 'push_events')

          expect { post path }
            .to change { disabled_hook.reload.permanently_disabled? }.from(true).to(false)
        end
      end

      context 'when the test rate limit is reached' do
        before do
          allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?)
            .with(anything, organization_owner, :web_hook_test,
              scope: { organization: organization, user: organization_owner })
            .and_return(true)
        end

        it 'does not execute the hook and returns 429', :aggregate_failures do
          endpoint = stub_hook_endpoint(hook)

          request

          expect(endpoint).not_to have_been_requested
          expect(response).to have_gitlab_http_status(:too_many_requests)
        end
      end

      it_behaves_like 'system hook lookup scoped to the organization' do
        def request_system_hook(hook)
          post test_organization_admin_settings_hook_path(organization, hook, trigger: 'push_events')
        end
      end
    end
  end
end
