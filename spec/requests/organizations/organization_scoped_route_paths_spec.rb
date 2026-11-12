# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization-prefixed route paths', feature_category: :organization do
  # rubocop:disable Gitlab/RSpec/AvoidCreateDefaultOrganization -- legacy paths live in the default organization
  let_it_be(:default_organization) { create(:organization, :default) }
  # rubocop:enable Gitlab/RSpec/AvoidCreateDefaultOrganization

  let_it_be(:organization) { create(:organization) }
  let_it_be(:other_organization) { create(:organization) }

  let_it_be(:legacy_group) { create(:group, :public, organization: default_organization) }
  let_it_be(:legacy_project) { create(:project, :public, group: legacy_group) }
  let_it_be(:unprefixed_group) { create(:group, :public, organization: organization) }

  let_it_be(:prefixed_group, freeze: false) { create(:group, :public, organization: organization) }
  let_it_be(:prefixed_project, freeze: false) { create(:project, :public, group: prefixed_group) }

  let_it_be(:user) { create(:user, :with_namespace) }

  let(:prefixed_group_path) { "o/#{organization.path}/#{prefixed_group.path}" }

  # Nothing writes prefixed routes yet. Renaming the root route is how a
  # prefixed row comes to exist here; it cascades to descendants and leaves a
  # redirect route for the old path.
  before_all do
    prefixed_group.route.update!(path: "o/#{organization.path}/#{prefixed_group.path}")
    prefixed_project.reload
  end

  before do
    sign_in(user)
  end

  describe 'prefixed paths' do
    it 'serves a group at its prefixed path' do
      get "/#{prefixed_group_path}"

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'serves a group sub-resource at its prefixed path' do
      get "/groups/#{prefixed_group_path}/-/activity"

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'serves a project at its prefixed path' do
      get "/#{prefixed_group_path}/#{prefixed_project.path}"

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'redirects to the canonical path when the prefix differs only in case' do
      get "/o/#{organization.path.upcase}/#{prefixed_group.path}"

      expect(response).to redirect_to("/#{prefixed_group_path}")
    end

    it 'is not served under a different organization' do
      get "/o/#{other_organization.path}/#{prefixed_group.path}"

      # Treated as a legacy link to the bare path, whose redirect route then
      # leads to the prefixed group.
      expect(response).to redirect_to("/#{prefixed_group.path}")
    end

    it 'redirects the old unprefixed path to the prefixed one' do
      get "/#{prefixed_group.path}"

      expect(response).to redirect_to("/#{prefixed_group_path}")
    end
  end

  describe 'unprefixed paths' do
    it 'serves a default-organization group at its unprefixed path' do
      get "/#{legacy_group.full_path}"

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'serves a default-organization project at its unprefixed path' do
      get "/#{legacy_project.full_path}"

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'serves a non-default-organization group at its unprefixed path' do
      get "/#{unprefixed_group.full_path}"

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'redirects the formerly cloned group URL to the canonical one' do
      get "/o/#{organization.path}/groups/#{unprefixed_group.full_path}"

      expect(response).to redirect_to("/groups/#{unprefixed_group.full_path}")
    end
  end

  describe 'organization-level pages' do
    # These stay cloned under /o/ and are drawn after the widened group wildcard;
    # they still resolve because no group can exist at a reserved first segment.
    it 'still routes the organization dashboard, which redirects to the global one' do
      get "/o/#{organization.path}/dashboard/projects"

      expect(response).to redirect_to('/dashboard/projects')
    end

    it 'still serves the organization activity page' do
      get "/o/#{organization.path}/-/activity"

      expect(response).to have_gitlab_http_status(:ok)
    end
  end
end
