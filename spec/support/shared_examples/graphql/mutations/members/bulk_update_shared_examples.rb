# frozen_string_literal: true

RSpec.shared_examples 'members bulk update mutation' do
  let_it_be(:current_user, freeze: false) { create(:user) }
  let_it_be(:user1, freeze: false) { create(:user) }
  let_it_be(:user2, freeze: false) { create(:user) }
  let_it_be(:member1, freeze: false) { create(member_type, source: source, user: user1) }
  let_it_be(:member2, freeze: false) { create(member_type, source: source, user: user2) }

  let(:extra_params) { { expires_at: 10.days.from_now } }
  let(:input_params) { input.merge(extra_params) }
  let(:mutation) { graphql_mutation(mutation_name, input_params) }
  let(:mutation_response) { graphql_mutation_response(mutation_name) }

  let(:input) do
    {
      source_id_key => source.to_global_id.to_s,
      'user_ids' => [user1.to_global_id.to_s, user2.to_global_id.to_s],
      'access_level' => 'GUEST'
    }
  end

  context 'when user is not logged-in' do
    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when user is not an owner' do
    before do
      source.add_developer(current_user)
    end

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when user is an owner' do
    before do
      source.add_owner(current_user)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_member do
      let(:user) { current_user }
      let(:boundary_object) { source }
      let(:mutation) { graphql_mutation(mutation_name, input_params, 'errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end

    shared_examples 'updates the user access role' do
      specify do
        post_graphql_mutation(mutation, current_user: current_user)

        new_access_levels = mutation_response[response_member_field].map do |member|
          member['accessLevel']['integerValue']
        end
        expect(response).to have_gitlab_http_status(:success)
        expect(mutation_response['errors']).to be_empty
        expect(new_access_levels).to all(be Gitlab::Access::GUEST)
      end
    end

    it_behaves_like 'updates the user access role'

    shared_examples 'returns a GraphQL error without updating the members' do
      it 'returns a top-level error and does not update the members', :aggregate_failures do
        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .not_to change { [member1, member2, parent_group_member].map { |member| member.reload.access_level } }

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_errors).to contain_exactly(a_hash_including('message' => error_message))
        expect(mutation_response).to be_nil
      end
    end

    context 'when inherited members are passed' do
      let(:error_message) { Mutations::Members::BulkUpdateBase::INVALID_MEMBERS_ERROR }
      let(:input) do
        {
          source_id_key => source.to_global_id.to_s,
          'user_ids' => [user1.to_global_id.to_s, user2.to_global_id.to_s, parent_group_member.user.to_global_id.to_s],
          'access_level' => 'GUEST'
        }
      end

      it_behaves_like 'returns a GraphQL error without updating the members'

      context 'when only inherited members are passed' do
        let(:input) do
          {
            source_id_key => source.to_global_id.to_s,
            'user_ids' => [parent_group_member.user.to_global_id.to_s],
            'access_level' => 'GUEST'
          }
        end

        it_behaves_like 'returns a GraphQL error without updating the members'
      end
    end

    context 'when members count is more than the allowed limit' do
      let(:error_message) { Mutations::Members::BulkUpdateBase::MAX_MEMBERS_UPDATE_ERROR }

      before do
        stub_const('Mutations::Members::BulkUpdateBase::MAX_MEMBERS_UPDATE_LIMIT', 1)
      end

      it_behaves_like 'returns a GraphQL error without updating the members'
    end

    context 'when the update service raises access denied error' do
      before do
        allow_next_instance_of(Members::UpdateService) do |instance|
          allow(instance).to receive(:execute).and_raise(Gitlab::Access::AccessDeniedError)
        end
      end

      it 'does not update the members' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response[response_member_field]).to be_nil
        expect(mutation_response['errors'])
          .to contain_exactly("Unable to update members, please check user permissions.")
      end
    end

    context 'when the update service returns an error message' do
      before do
        allow_next_instance_of(Members::UpdateService) do |instance|
          error_result = {
            message: 'Expires at cannot be a date in the past',
            status: :error,
            members: [member1]
          }
          allow(instance).to receive(:execute).and_return(error_result)
        end
      end

      it 'passes through the error' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response[response_member_field].first['id']).to eq(member1.to_global_id.to_s)
        expect(mutation_response['errors']).to contain_exactly('Expires at cannot be a date in the past')
      end
    end
  end
end
