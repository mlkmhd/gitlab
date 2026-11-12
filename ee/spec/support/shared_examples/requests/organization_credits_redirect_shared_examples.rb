# frozen_string_literal: true

# Requires `group_credits_path`, a lambda that takes a group and returns the page path.
RSpec.shared_examples 'a group credits page billed through the Organization' do
  context 'when the group is billed through its Organization', :saas do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:billed_organization) { create(:organization) }
    let_it_be(:organization_gitlab_subscription) do
      create(:organization_gitlab_subscription, organization: billed_organization)
    end

    let_it_be(:nominated_group) { billed_organization.billing_namespace }
    let_it_be(:other_group) { create(:group, organization: billed_organization) }
    let_it_be(:group_owner) { create(:user) }
    let_it_be(:organization_owner) { create(:user, owner_of: billed_organization) }

    let(:billed_group) { public_send(group_name) }
    let(:message) do
      s_('UsageBilling|GitLab Credits for this group are managed by your organization. ' \
        'Contact an organization Owner to view usage or change limits.')
    end

    subject(:request) { get group_credits_path.call(billed_group) }

    before_all do
      [nominated_group, other_group].each do |group|
        group.add_owner(group_owner)
        group.add_owner(organization_owner)
      end
    end

    before do
      stub_ee_application_setting(should_check_namespace_plan: true)
    end

    where(:group_name) { %i[nominated_group other_group] }

    with_them do
      context 'when the user is an Organization owner' do
        before do
          sign_in(organization_owner)
        end

        it 'redirects to the Organization credits page' do
          request

          expect(response).to redirect_to(gitlab_credits_dashboard_organization_path(billed_organization))
        end
      end

      context 'when the user is a group Owner but not an Organization owner' do
        before do
          sign_in(group_owner)
        end

        it 'renders the managed by your organization message', :aggregate_failures do
          request

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.body).to include(message)
        end
      end

      context 'when the user is not a group Owner' do
        let_it_be(:maintainer) { create(:user) }

        before_all do
          nominated_group.add_maintainer(maintainer)
          other_group.add_maintainer(maintainer)
        end

        before do
          sign_in(maintainer)
        end

        it 'returns 404' do
          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when organization_billing is disabled' do
        before do
          stub_feature_flags(organization_billing: false)
          sign_in(organization_owner)
        end

        it 'does not redirect or render the message', :aggregate_failures do
          request

          expect(response).not_to redirect_to(gitlab_credits_dashboard_organization_path(billed_organization))
          expect(response.body).not_to include(message)
        end
      end
    end

    context 'when a group Owner opens a group that is not the nominated group' do
      let(:group_name) { :other_group }

      before do
        sign_in(group_owner)
      end

      it 'does not reference the nominated group' do
        request

        expect(response.body).not_to include(nominated_group.full_path)
      end
    end
  end
end
