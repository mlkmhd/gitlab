# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Organizations, feature_category: :organization do
  include WorkhorseHelpers

  let_it_be(:user) { create(:user) }

  shared_examples 'organization avatar upload' do
    context 'when valid' do
      let(:file_path) { 'spec/fixtures/banana_sample.gif' }

      it 'returns avatar url in response' do
        make_upload_request

        organization_id = json_response['id']
        avatar_url = "http://localhost/uploads/-/system/organizations/organization_detail/avatar/#{organization_id}/banana_sample.gif"
        expect(json_response['avatar_url']).to start_with(avatar_url)
      end
    end

    context 'when invalid' do
      shared_examples 'invalid file upload request' do
        it 'returns 400', :aggregate_failures do
          make_upload_request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(response.message).to eq('Bad Request')
          expect(json_response['message'].to_s).to match(/#{message}/)
        end
      end

      context 'when file format is not supported' do
        let(:file_path) { 'spec/fixtures/doc_sample.txt' }
        let(:message) { 'file format is not supported. Please try one of the following supported formats: image/png' }

        it_behaves_like 'invalid file upload request'
      end

      context 'when file is too large' do
        let(:file_path) { 'spec/fixtures/big-image.png' }
        let(:message)   { 'is too big' }

        it_behaves_like 'invalid file upload request'
      end
    end
  end

  describe 'POST /organizations' do
    let(:base_params) do
      {
        name: 'New Organization',
        path: 'new-org',
        description: 'A new organization'
      }
    end

    let(:params) { base_params }

    context 'when on GitLab.com', :saas do
      it_behaves_like 'authorizing granular token permissions', :create_organization do
        let(:boundary_object) { :instance }
        let(:request) { post api('/organizations', personal_access_token: pat), params: base_params }
      end
    end

    context 'when user is not authorized' do
      it 'returns unauthorized' do
        post api("/organizations"), params: params

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when release flag is disabled' do
      before do
        stub_organization_release(org_creation: false)
      end

      it 'returns forbidden' do
        post api("/organizations", user), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when on self-managed' do
      it 'returns forbidden' do
        post api("/organizations", user), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when user is authorized', :saas do
      it_behaves_like 'organization avatar upload' do
        def make_upload_request
          params_with_file_upload = params.merge(avatar: fixture_file_upload(file_path))

          workhorse_form_with_file(
            api('/organizations', user),
            method: :post,
            file_key: :avatar,
            params: params_with_file_upload
          )
        end
      end

      it_behaves_like 'rate limited endpoint', rate_limit_key: :create_organization_api do
        let_it_be(:user2) { create(:user) }

        let(:current_user) { user }

        def request
          post api("/organizations", user), params: params
        end

        def request_with_second_scope
          post api("/organizations", user2), params: params
        end
      end

      shared_examples 'returns bad request' do
        specify do
          post api("/organizations", user), params: params

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      it 'creates a new organization' do
        post api("/organizations", user), params: params

        expect(response).to have_gitlab_http_status(:success)
        expect(json_response['name']).to eq('New Organization')
        expect(json_response['path']).to eq('new-org')
        expect(json_response['description']).to eq('A new organization')
        expect(json_response['visibility']).to eq('private')
      end

      context 'when visibility is provided' do
        it 'creates a public organization' do
          post api("/organizations", user), params: base_params.merge(visibility: 'public')

          expect(response).to have_gitlab_http_status(:success)
          expect(json_response['visibility']).to eq('public')
        end

        it 'returns error for internal organization' do
          post api("/organizations", user), params: base_params.merge(visibility: 'internal')

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to eq('visibility does not have a valid value')
        end
      end

      context 'when optional params are missing' do
        context 'with missing description' do
          let(:params) { base_params.except(:description) }

          it 'creates a new organization' do
            post api("/organizations", user), params: params

            expect(response).to have_gitlab_http_status(:success)
            expect(json_response['name']).to eq('New Organization')
            expect(json_response['path']).to eq('new-org')
          end
        end
      end

      context 'when required params are missing' do
        context 'with missing name' do
          let(:params) { base_params.except(:name) }

          it_behaves_like 'returns bad request'
        end

        context 'with missing path' do
          let(:params) { base_params.except(:path) }

          it_behaves_like 'returns bad request'
        end
      end

      context 'when organization creation fails' do
        it 'returns an error message' do
          message = _('Failed to create organization')
          allow_next_instance_of(::Organizations::CreateService) do |service|
            allow(service).to receive(:execute).and_return(ServiceResponse.error(message: Array(message)))
          end

          post api("/organizations", user), params: params

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to match_array(message)
        end
      end

      context 'when organization creation is disable by admin' do
        before do
          stub_application_setting(can_create_organization: false)
        end

        it 'returns forbidden' do
          post api("/organizations", user), params: params

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end
    end
  end

  describe 'DELETE /organizations/:id' do
    let_it_be_with_refind(:organization) { create(:organization) }

    it_behaves_like 'authorizing granular token permissions', :delete_organization do
      let(:boundary_object) { :instance }
      let(:request) { delete api("/organizations/#{organization.id}", personal_access_token: pat) }

      before do
        create(:organization_user, :owner, organization: organization, user: user)
      end
    end

    context 'when user is not authenticated' do
      it 'returns unauthorized' do
        delete api("/organizations/#{organization.id}")

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when user does not have permission' do
      it 'returns forbidden with an error message' do
        delete api("/organizations/#{organization.id}", user)

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to eq('Insufficient permissions')
      end
    end

    context 'when user has permission' do
      before_all do
        create(:organization_user, :owner, organization: organization, user: user)
      end

      context 'when organization does not exist' do
        it 'returns not found' do
          delete api("/organizations/#{non_existing_record_id}", user)

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when organization is not empty' do
        before do
          create(:group, organization: organization)
        end

        it 'returns bad request with an error message' do
          delete api("/organizations/#{organization.id}", user)

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to eq('Organization must be empty before it can be deleted')
        end
      end

      context 'when organization is already soft-deleted' do
        before do
          ::Organizations::SoftDeleteService.new(organization, current_user: user).execute
          organization.reload
        end

        it 'returns bad request with an error message' do
          delete api("/organizations/#{organization.id}", user)

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to eq('Organization has already been deleted')
        end
      end

      context 'when organization is empty and not default' do
        it 'soft-deletes the organization and returns accepted' do
          expect { delete api("/organizations/#{organization.id}", user) }
            .to change { organization.reload.state }.from('active').to('soft_deleted')

          expect(response).to have_gitlab_http_status(:accepted)
        end
      end
    end
  end

  describe 'POST /organizations/:id/restore' do
    let_it_be(:admin) { create(:admin) }
    let_it_be_with_refind(:organization) { create(:organization) }

    let(:path) { "/organizations/#{organization.id}/restore" }

    it_behaves_like 'authorizing granular token permissions', :restore_organization do
      let(:boundary_object) { :instance }
      let(:user) { admin }
      let(:request) { post api(path, personal_access_token: pat) }

      before do
        organization.soft_delete(transition_user: admin)
      end
    end

    context 'when user is not authenticated' do
      it 'returns unauthorized' do
        post api(path)

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when the organization is soft-deleted' do
      before do
        organization.soft_delete(transition_user: admin)
      end

      context 'when user is an organization owner but not an administrator' do
        before_all do
          create(:organization_user, :owner, organization: organization, user: user)
        end

        it 'returns forbidden and does not restore the organization' do
          expect { post api(path, user) }.not_to change { organization.reload.state }

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      context 'when user is an administrator without admin mode' do
        it 'returns forbidden and does not restore the organization' do
          expect { post api(path, admin, admin_mode: false) }.not_to change { organization.reload.state }

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      context 'when user is an administrator' do
        it 'restores the organization and returns it', :aggregate_failures do
          expect { post api(path, admin, admin_mode: true) }
            .to change { organization.reload.state }.from('soft_deleted').to('active')

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response['id']).to eq(organization.id)
          expect(json_response['path']).to eq(organization.path)
        end
      end
    end

    context 'when user is an administrator and the organization cannot be restored' do
      context 'when organization does not exist' do
        it 'returns not found' do
          post api("/organizations/#{non_existing_record_id}/restore", admin, admin_mode: true)

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when organization is not soft-deleted' do
        it 'returns bad request with an error message', :aggregate_failures do
          post api(path, admin, admin_mode: true)

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to eq('Organization is not soft-deleted')
          expect(organization.reload.state).to eq('active')
        end
      end
    end
  end

  describe 'POST /organizations/:id/transfer_users' do
    let_it_be(:admin) { create(:admin) }
    let_it_be(:source_organization) { create(:organization) }
    let_it_be_with_refind(:target_organization) { create(:organization) }
    let_it_be_with_refind(:user_1) { create(:user, organization: source_organization) }
    let_it_be_with_refind(:user_2) { create(:user, organization: source_organization) }

    let(:path) { "/organizations/#{target_organization.id}/transfer_users" }
    let(:params) { { user_ids: [user_1.id, user_2.id] } }

    it_behaves_like 'authorizing granular token permissions', :transfer_user do
      let(:boundary_object) { :instance }
      let(:user) { admin }
      let(:request) { post api(path, personal_access_token: pat), params: params }
    end

    context 'when user is not authenticated' do
      it 'returns unauthorized' do
        post api(path), params: params

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when user is an organization owner but not an administrator' do
      before_all do
        create(:organization_user, :owner, organization: target_organization, user: user)
      end

      it 'returns forbidden and does not enqueue the transfer' do
        expect(Organizations::TransferUsersWorker).not_to receive(:perform_async)

        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when user is an administrator without admin mode' do
      it 'returns forbidden and does not enqueue the transfer' do
        expect(Organizations::TransferUsersWorker).not_to receive(:perform_async)

        post api(path, admin, admin_mode: false), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when user is an administrator' do
      subject(:request) { post api(path, admin, admin_mode: true), params: params }

      it 'enqueues the transfer and returns the user IDs', :aggregate_failures do
        expect(Organizations::TransferUsersWorker).to receive(:perform_async).with(
          { 'user_ids' => match_array([user_1.id, user_2.id]), 'organization_id' => target_organization.id }
        )

        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(json_response).to eq(
          'organization_id' => target_organization.id,
          'user_ids' => [user_1.id, user_2.id]
        )
      end

      context 'when user IDs are duplicated' do
        let(:params) { { user_ids: [user_1.id, user_1.id] } }

        it 'enqueues the user once' do
          expect(Organizations::TransferUsersWorker).to receive(:perform_async).with(
            { 'user_ids' => [user_1.id], 'organization_id' => target_organization.id }
          )

          request

          expect(response).to have_gitlab_http_status(:accepted)
          expect(json_response['user_ids']).to eq([user_1.id])
        end
      end

      context 'when the organization does not exist' do
        let(:path) { "/organizations/#{non_existing_record_id}/transfer_users" }

        it 'returns not found' do
          expect(Organizations::TransferUsersWorker).not_to receive(:perform_async)

          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when a user does not exist' do
        let(:params) { { user_ids: [user_1.id, non_existing_record_id] } }

        it 'returns not found and does not enqueue the transfer' do
          expect(Organizations::TransferUsersWorker).not_to receive(:perform_async)

          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when the users belong to different organizations' do
        let_it_be(:other_user) { create(:user, organization: create(:organization)) }

        let(:params) { { user_ids: [user_1.id, other_user.id] } }

        it 'returns bad request and does not enqueue the transfer', :aggregate_failures do
          expect(Organizations::TransferUsersWorker).not_to receive(:perform_async)

          request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include('Cannot transfer users to a different organization')
        end
      end

      context 'when the users are already in the target organization' do
        let(:params) { { user_ids: [create(:user, organization: target_organization).id] } }

        it 'returns bad request' do
          request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to eq('Users are already in the target organization.')
        end
      end

      context 'when a user is internal' do
        let_it_be(:bot) { create(:user, :security_bot, organization: source_organization) }

        let(:params) { { user_ids: [user_1.id, bot.id] } }

        it 'returns bad request and does not enqueue the transfer', :aggregate_failures do
          expect(Organizations::TransferUsersWorker).not_to receive(:perform_async)

          request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to eq(
            'Internal users such as the ghost user and bots cannot be transferred.'
          )
        end
      end

      context 'when a user is a service account' do
        let_it_be(:service_account) { create(:service_account, organization: source_organization) }

        let(:params) { { user_ids: [user_1.id, service_account.id] } }

        it 'enqueues the transfer', :aggregate_failures do
          expect(Organizations::TransferUsersWorker).to receive(:perform_async)

          request

          expect(response).to have_gitlab_http_status(:accepted)
        end
      end

      context 'when user_ids is missing' do
        let(:params) { {} }

        it 'returns bad request' do
          request

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when user_ids is empty' do
        let(:params) { { user_ids: [] } }

        it 'returns bad request' do
          request

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when user_ids exceeds the maximum' do
        let(:max) { Organizations::Transfer::UsersService::BATCH_SIZE }
        let(:params) { { user_ids: (1..(max + 1)).to_a } }

        it 'returns bad request and does not enqueue the transfer', :aggregate_failures do
          expect(Organizations::TransferUsersWorker).not_to receive(:perform_async)

          request

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to include("user_ids must contain at most #{max} items")
        end
      end
    end
  end

  describe 'organization users' do
    let_it_be(:admin) { create(:admin) }
    let_it_be(:organization) { create(:organization) }
    let_it_be(:owner) { create(:user, organizations: [organization]) }
    let_it_be(:other_user) { create(:user, organizations: [organization]) }
    let_it_be(:third_user) { create(:user, organizations: [organization]) }

    let(:path) { "/organizations/#{organization.id}/users" }

    before_all do
      # The user factory already creates the memberships, so only promote the owner.
      Organizations::OrganizationUser.find_by!(organization: organization, user: owner).update!(access_level: :owner)
    end

    describe 'GET /organizations/:id/users' do
      it_behaves_like 'authorizing granular token permissions', :read_organization_user do
        let(:boundary_object) { :instance }
        let(:user) { admin }
        let(:request) { get api(path, personal_access_token: pat) }
      end

      it 'returns unauthorized when not authenticated' do
        get api(path)

        expect(response).to have_gitlab_http_status(:unauthorized)
      end

      it 'returns forbidden when the user is not a member' do
        get api(path, user)

        expect(response).to have_gitlab_http_status(:forbidden)
      end

      it 'lists all organization users for an owner', :aggregate_failures do
        get api(path, owner)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response.pluck('id')).to contain_exactly(owner.id, other_user.id, third_user.id)
        expect(json_response.find { |u| u['id'] == owner.id }).to include('access_level' => 'owner', 'bot' => false)
      end

      it 'orders by id ascending by default' do
        get api(path, owner)

        expect(json_response.pluck('id')).to eq(organization.organization_users.order(:id).pluck(:user_id))
      end

      it 'supports descending order' do
        get api(path, owner), params: { sort: 'desc' }

        expect(json_response.pluck('id')).to eq(organization.organization_users.order(id: :desc).pluck(:user_id))
      end

      it_behaves_like 'rate limited endpoint', rate_limit_key: :organization_user_list do
        let(:current_user) { owner }

        def request
          get api(path, owner)
        end

        def request_with_second_scope
          get api(path, other_user)
        end
      end

      context 'with keyset pagination' do
        it 'returns a cursor link for the next page and no duplicates', :aggregate_failures do
          get api(path, owner), params: { per_page: 2 }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response.size).to eq(2)
          expect(response.headers['Link']).to include('cursor=')

          first_page_ids = json_response.pluck('id')

          get api(path, owner), params: { per_page: 2, cursor: next_cursor }

          expect(json_response.size).to eq(1)
          expect(json_response.pluck('id') & first_page_ids).to be_empty
        end

        it 'rejects offset pagination' do
          get api(path, owner), params: { pagination: 'legacy' }

          expect(response).to have_gitlab_http_status(:bad_request)
        end

        it 'ignores the page parameter' do
          get api(path, owner), params: { per_page: 2, page: 2 }

          expect(json_response.size).to eq(2)
          expect(response.headers).not_to include('X-Page')
        end

        def next_cursor
          Rack::Utils.parse_query(URI.parse(response.headers['Link'][/<(.+)>; rel="next"/, 1]).query)['cursor']
        end
      end

      it 'avoids N+1 queries' do
        get api(path, owner) # warm caches

        control = ActiveRecord::QueryRecorder.new { get api(path, owner) }

        create(:organization_user, organization: organization)

        expect { get api(path, owner) }.not_to exceed_query_limit(control)
      end
    end

    describe 'POST /organizations/:id/users' do
      let_it_be(:new_user) { create(:user) }

      it_behaves_like 'authorizing granular token permissions', :create_organization_user do
        let(:boundary_object) { :instance }
        let(:user) { admin }
        let(:request) { post api(path, personal_access_token: pat), params: { username: new_user.username } }
      end

      it_behaves_like 'rate limited endpoint', rate_limit_key: :organization_user_create do
        let(:current_user) { owner }

        def request
          post api(path, owner), params: { username: new_user.username }
        end

        def request_with_second_scope
          post api(path, admin, admin_mode: true), params: { username: new_user.username }
        end
      end

      it 'returns forbidden for a non-owner member' do
        post api(path, other_user), params: { username: new_user.username }

        expect(response).to have_gitlab_http_status(:forbidden)
      end

      it 'adds the user as an owner', :aggregate_failures do
        expect { post api(path, owner), params: { username: new_user.username, access_level: 'owner' } }
          .to change { organization.organization_users.owners.count }.by(1)

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response).to include('id' => new_user.id, 'access_level' => 'owner')
      end

      it 'adds the user with the default access level', :aggregate_failures do
        post api(path, owner), params: { username: new_user.username }

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response['access_level']).to eq('default')
      end

      it 'returns bad request when the user does not exist' do
        post api(path, owner), params: { username: 'does-not-exist' }

        expect(response).to have_gitlab_http_status(:bad_request)
      end

      it 'returns bad request when the user is already a member' do
        post api(path, owner), params: { username: other_user.username }

        expect(response).to have_gitlab_http_status(:bad_request)
      end

      it 'returns bad request for an invalid access level' do
        post api(path, owner), params: { username: new_user.username, access_level: 'admin' }

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    describe 'PUT /organizations/:id/users/:user_id' do
      let(:put_path) { "#{path}/#{other_user.id}" }

      it_behaves_like 'authorizing granular token permissions', :update_organization_user do
        let(:boundary_object) { :instance }
        let(:user) { admin }
        let(:request) { put api(put_path, personal_access_token: pat), params: { access_level: 'owner' } }
      end

      it_behaves_like 'rate limited endpoint', rate_limit_key: :organization_user_update do
        let(:current_user) { owner }

        def request
          put api("#{path}/#{non_existing_record_id}", owner), params: { access_level: 'owner' }
        end

        def request_with_second_scope
          put api("#{path}/#{non_existing_record_id}", admin, admin_mode: true), params: { access_level: 'owner' }
        end
      end

      it 'returns unauthorized when not authenticated' do
        put api(put_path), params: { access_level: 'owner' }

        expect(response).to have_gitlab_http_status(:unauthorized)
      end

      it 'promotes a member to owner for an owner', :aggregate_failures do
        expect { put api(put_path, owner), params: { access_level: 'owner' } }
          .to change { organization.organization_users.find_by(user: other_user).access_level }
          .from('default').to('owner')

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include('id' => other_user.id, 'access_level' => 'owner')
      end

      it 'promotes a member to owner for an administrator', :aggregate_failures do
        put api(put_path, admin, admin_mode: true), params: { access_level: 'owner' }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['access_level']).to eq('owner')
      end

      it 'returns forbidden when a non-owner member promotes themselves', :aggregate_failures do
        expect { put api(put_path, other_user), params: { access_level: 'owner' } }
          .not_to change { organization.organization_users.owners.count }

        expect(response).to have_gitlab_http_status(:forbidden)
      end

      it 'returns the same forbidden response to a non-owner member whether or not the target is a member' do
        put api("#{path}/#{non_existing_record_id}", other_user), params: { access_level: 'owner' }

        expect(response).to have_gitlab_http_status(:forbidden)
      end

      it 'returns not found when the user is not in the organization' do
        put api("#{path}/#{non_existing_record_id}", owner), params: { access_level: 'owner' }

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'returns bad request for an unknown access level' do
        put api(put_path, owner), params: { access_level: 'maintainer' }

        expect(response).to have_gitlab_http_status(:bad_request)
      end

      it 'returns bad request when demoting the last owner', :aggregate_failures do
        expect { put api("#{path}/#{owner.id}", owner), params: { access_level: 'default' } }
          .not_to change { organization.organization_users.owners.count }

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    describe 'DELETE /organizations/:id/users/:user_id' do
      # A user cannot leave their home organization, so the removable member's home organization is another one.
      let_it_be(:home_organization) { create(:organization) }
      let_it_be(:member) { create(:user, organization: home_organization) }

      let(:delete_path) { "#{path}/#{member.id}" }

      before_all do
        create(:organization_user, organization: organization, user: member)
      end

      it_behaves_like 'authorizing granular token permissions', :delete_organization_user do
        let(:boundary_object) { :instance }
        let(:user) { admin }
        let(:request) { delete api(delete_path, personal_access_token: pat) }
      end

      it_behaves_like 'rate limited endpoint', rate_limit_key: :organization_user_delete do
        let(:current_user) { owner }

        def request
          delete api("#{path}/#{non_existing_record_id}", owner)
        end

        def request_with_second_scope
          delete api("#{path}/#{non_existing_record_id}", admin, admin_mode: true)
        end
      end

      it 'returns forbidden for a non-owner member' do
        delete api("#{path}/#{owner.id}", other_user)

        expect(response).to have_gitlab_http_status(:forbidden)
      end

      it 'returns not found when the user is not in the organization' do
        delete api("#{path}/#{non_existing_record_id}", owner)

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'returns the same forbidden response to a non-owner member whether or not the target is a member' do
        delete api("#{path}/#{non_existing_record_id}", other_user)

        expect(response).to have_gitlab_http_status(:forbidden)
      end

      it 'removes the user from the organization' do
        expect { delete api(delete_path, owner) }
          .to change { organization.organization_users.where(user: member).count }.from(1).to(0)

        expect(response).to have_gitlab_http_status(:no_content)
      end

      it 'returns bad request when removing the user from their home organization', :aggregate_failures do
        expect { delete api("#{path}/#{other_user.id}", owner) }
          .not_to change { organization.organization_users.count }

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['message']).to include('home organization')
      end

      it 'returns forbidden when the service denies permission', :aggregate_failures do
        error = ServiceResponse.error(message: ['No permission'], reason: :forbidden)
        allow_next_instance_of(::Organizations::OrganizationUsers::DestroyService) do |service|
          allow(service).to receive(:execute).and_return(error)
        end

        delete api(delete_path, owner)

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to eq('No permission')
      end

      context 'when removing yourself' do
        it 'lets a non-owner member leave an organization that is not their home organization' do
          expect { delete api(delete_path, member) }
            .to change { organization.organization_users.where(user: member).count }.from(1).to(0)

          expect(response).to have_gitlab_http_status(:no_content)
        end

        it 'returns bad request for the home organization', :aggregate_failures do
          expect { delete api("#{path}/#{other_user.id}", other_user) }
            .not_to change { organization.organization_users.count }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include('home organization')
        end
      end

      context 'when the user is the last owner' do
        let_it_be(:solo_organization) { create(:organization) }
        let_it_be(:solo_owner) { create(:user, organization: home_organization) }

        before_all do
          create(:organization_user, :owner, organization: solo_organization, user: solo_owner)
        end

        it 'returns bad request and keeps the owner', :aggregate_failures do
          expect do
            delete api("/organizations/#{solo_organization.id}/users/#{solo_owner.id}", solo_owner)
          end.not_to change { solo_organization.organization_users.owners.count }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include('last owner')
        end
      end
    end
  end
end
