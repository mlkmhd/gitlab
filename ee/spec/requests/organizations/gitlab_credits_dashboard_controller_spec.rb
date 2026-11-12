# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::GitlabCreditsDashboardController, :saas, feature_category: :consumables_cost_management do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:owner) { create(:user, owner_of: organization) }
  let_it_be(:member) { create(:user, organization: organization) }
  let_it_be(:nominated_group_owner) { create(:user) }
  let_it_be(:organization_gitlab_subscription) do
    create(:organization_gitlab_subscription, organization: organization)
  end

  let_it_be(:nominated_group) { organization.billing_namespace }

  let(:dashboard_path) { gitlab_credits_dashboard_organization_path(organization) }

  subject(:gitlab_request) { get dashboard_path }

  before do
    stub_ee_application_setting(should_check_namespace_plan: true)
  end

  def mount_element
    Nokogiri::HTML.parse(response.body).at_css('#js-organization-usage-billing-dashboard')
  end

  shared_examples 'a hidden dashboard' do
    it 'returns not found and does not render the mount', :aggregate_failures do
      gitlab_request

      expect(response).to have_gitlab_http_status(:not_found)
      expect(mount_element).to be_nil
    end
  end

  describe 'GET #show' do
    context 'when the user is an organization owner' do
      before do
        sign_in(owner)
      end

      it 'renders the mount with the organization ID and no reference to the nominated group',
        :aggregate_failures do
        gitlab_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(mount_element['data-organization-id']).to eq(organization.to_global_id.to_s)
        expect(response.body).not_to include(nominated_group.full_path)
        expect(response.body).not_to include("gl_namespace_id=#{nominated_group.id}")
      end

      context 'for display_gitlab_credits_user_data' do
        where(:enabled) { [true, false] }

        with_them do
          before do
            nominated_group.namespace_settings.update!(display_gitlab_credits_user_data: enabled)
          end

          it "pushes the nominated group's setting to the frontend" do
            gitlab_request

            expect(response.body).to include("gon.display_gitlab_credits_user_data=#{enabled}")
          end
        end
      end

      it_behaves_like 'organization - action disabled by org_pages release flag'

      context 'when the organization_billing feature flag is disabled' do
        before do
          stub_feature_flags(organization_billing: false)
        end

        it_behaves_like 'a hidden dashboard'
      end

      context 'when the nominated group is not entitled to GitLab Credits' do
        let_it_be(:free_organization) { create(:organization, owners: owner) }
        let_it_be(:free_organization_gitlab_subscription) do
          create(:organization_gitlab_subscription, organization: free_organization,
            gitlab_subscription: create(:gitlab_subscription, :free,
              namespace: create(:group, organization: free_organization)))
        end

        let(:dashboard_path) { gitlab_credits_dashboard_organization_path(free_organization) }

        it_behaves_like 'a hidden dashboard'
      end

      context 'when the organization has no billing namespace' do
        let_it_be(:unbilled_organization) { create(:organization, owners: owner) }

        let(:dashboard_path) { gitlab_credits_dashboard_organization_path(unbilled_organization) }

        it_behaves_like 'a hidden dashboard'
      end
    end

    context 'when the user is an organization member who is not an owner' do
      before do
        sign_in(member)
      end

      it_behaves_like 'a hidden dashboard'
    end

    context "when the user owns the nominated group but not the organization" do
      before_all do
        nominated_group.add_owner(nominated_group_owner)
      end

      before do
        sign_in(nominated_group_owner)
      end

      it_behaves_like 'a hidden dashboard'
    end

    context 'when the user is not signed in' do
      it 'redirects to the sign in page' do
        gitlab_request

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
