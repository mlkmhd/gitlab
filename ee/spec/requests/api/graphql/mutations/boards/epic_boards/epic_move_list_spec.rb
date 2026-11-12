# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Reposition and move epic between board lists', feature_category: :planning_views do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:development) { create(:group_label, group: group, name: 'Development') }
  let(:epic) { create(:epic, group: group) }

  let_it_be(:board) { create(:epic_board, group: group) }
  let_it_be(:backlog) { create(:epic_list, epic_board: board, list_type: :backlog) }
  let_it_be(:labeled_list) { create(:epic_list, epic_board: board, label: development) }

  let(:mutation_class) { Mutations::Boards::EpicBoards::EpicMoveList }
  let(:mutation_name) { mutation_class.graphql_name }

  let(:params) do
    {
      board_id: global_id_of(board),
      epic_id: global_id_of(epic)
    }
  end

  let(:move_params) do
    {
      from_list_id: global_id_of(backlog),
      to_list_id: global_id_of(labeled_list)
    }
  end

  subject(:mutation_request) { post_graphql_mutation(mutation(params), current_user: current_user) }

  context 'when epics are available' do
    before do
      stub_licensed_features(epics: true)
    end

    context 'when user does not have permissions to admin the board' do
      it 'raises resource not available error' do
        mutation_request

        message = Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR
        expect(graphql_errors).to include(a_hash_including('message' => message))
      end
    end

    context 'when user has permissions to admin the board' do
      before_all do
        group.add_developer(current_user)
      end

      context 'when required move params are missing' do
        let(:move_params) { { to_list_id: global_id_of(backlog) } }

        it 'raises an error' do
          mutation_request

          message = 'At least one of the following parameters is required: fromListId, moveAfterId, moveBeforeId, positionInList.'
          expect(graphql_errors).to include(a_hash_including('message' => message))
        end
      end

      context 'when positionInList param is invalid' do
        let(:base_params) { { to_list_id: global_id_of(backlog), position_in_list: 1 } }

        context 'when move_before_id is also given' do
          let(:move_params) { base_params.merge({ move_before_id: global_id_of(epic) }) }

          it 'raises an error' do
            mutation_request

            message = 'positionInList is mutually exclusive with any of moveBeforeId or moveAfterId'
            expect(graphql_errors).to include(a_hash_including('message' => message))
          end
        end

        context 'when move_after_id is also given' do
          let(:move_params) { base_params.merge({ move_after_id: global_id_of(epic) }) }

          it 'raises an error' do
            mutation_request

            message = 'positionInList is mutually exclusive with any of moveBeforeId or moveAfterId'
            expect(graphql_errors).to include(a_hash_including('message' => message))
          end
        end

        context 'when position_in_list is invalid' do
          let(:move_params) { base_params.merge({ position_in_list: -5 }) }

          it 'raises an error' do
            mutation_request

            message = "positionInList must be >= 0 or #{Boards::Epics::MoveService::LIST_END_POSITION}"
            expect(graphql_errors).to include(a_hash_including('message' => message))
          end
        end
      end

      context 'moving an epic to another list' do
        # rubocop: disable CodeReuse/ActiveRecord
        it 'moves the epic to another list' do
          expect { mutation_request }.to change { epic.reload.labels }.from([]).to([development])
        end
        # rubocop: enable CodeReuse/ActiveRecord
      end

      context 'repositioning an epic' do
        let!(:epic1) { create(:epic, group: group) }
        let!(:epic_board_position) { create(:epic_board_position, epic_board: board, epic: epic1) }
        let!(:epic2) { create(:epic, group: group) }
        let!(:epic3) { create(:epic, group: group) }

        def position(epic)
          epic.epic_board_positions.first.relative_position
        end

        context 'when both move_before_id and move_after_id params are present' do
          let(:move_params) do
            {
              move_before_id: global_id_of(epic3),
              move_after_id: global_id_of(epic2),
              to_list_id: global_id_of(backlog)
            }
          end

          it 'repositions the epic' do
            mutation_request

            expect(position(epic)).to be > position(epic3)
          end
        end

        context 'when only move_before_id param is present' do
          let(:move_params) do
            {
              to_list_id: global_id_of(backlog),
              move_before_id: global_id_of(epic3)
            }
          end

          it 'repositions the epic' do
            mutation_request

            expect(position(epic)).to be > position(epic3)
          end
        end

        context 'when only move_after_id param is present' do
          let(:move_params) do
            {
              to_list_id: global_id_of(backlog),
              move_after_id: global_id_of(epic3)
            }
          end

          it 'repositions the epic' do
            mutation_request

            expect(position(epic)).to be < position(epic3)
          end
        end

        context 'when position_in_list param is present' do
          before do
            create(:epic_board_position, epic_board: board, epic: epic2, relative_position: 1000)
            create(:epic_board_position, epic_board: board, epic: epic3, relative_position: 2000)
          end

          let(:move_params) do
            {
              position_in_list: position_in_list,
              to_list_id: global_id_of(backlog)
            }
          end

          context 'when moving an epic to the beginning of the list' do
            let(:position_in_list) { 0 }

            it 'repositions the epic' do
              mutation_request

              expect(position(epic)).to be < position(epic2)
              expect(position(epic)).to be < position(epic3)
            end
          end

          context 'when moving an epic to the bottom of the list' do
            let(:position_in_list) { -1 }

            it 'repositions the epic' do
              mutation_request

              expect(position(epic)).to be > position(epic2)
              expect(position(epic)).to be > position(epic3)
            end
          end
        end
      end
    end

    context 'with the epic move list rate limit' do
      let_it_be(:other_developer) { create(:user, developer_of: group) }

      before_all do
        group.add_developer(current_user)
      end

      it_behaves_like 'rate limited endpoint', rate_limit_key: :epic_move_list, graphql: true do
        def request
          post_graphql_mutation(mutation(params), current_user: current_user)
        end

        def request_with_second_scope
          post_graphql_mutation(mutation(params), current_user: other_developer)
        end
      end

      context 'when the limit is reached', :freeze_time, :clean_gitlab_redis_rate_limiting do
        before do
          stub_application_setting(epic_move_list_limit: 1)
        end

        it 'counts each alias against the limit' do
          query = <<~GQL
            mutation($input: EpicMoveListInput!) {
              first: epicMoveList(input: $input) { errors }
              second: epicMoveList(input: $input) { errors }
            }
          GQL
          input = {
            boardId: global_id_of(board).to_s,
            epicId: global_id_of(epic).to_s,
            fromListId: global_id_of(backlog).to_s,
            toListId: global_id_of(labeled_list).to_s
          }

          post_graphql(query, current_user: current_user, variables: { input: input })

          expect_graphql_errors_to_include(Gitlab::ApplicationRateLimiter.throttled_error_message)
          expect(epic.reload.labels).to contain_exactly(development)
        end

        context 'when the epic_move_list_rate_limit feature flag is disabled' do
          before do
            stub_feature_flags(epic_move_list_rate_limit: false)
          end

          it 'counts the moves in log mode without throttling', :aggregate_failures do
            states = []
            allow(Gitlab::Instrumentation::RateLimitState).to receive(:track).and_wrap_original do |original, *args|
              original.call(*args)
              states.concat(Gitlab::Instrumentation::RateLimitState.payload.fetch(:rate_limit_state, []))
            end

            2.times { post_graphql_mutation(mutation(params), current_user: current_user) }

            expect_graphql_errors_to_be_empty
            expect(states).to include('applimiter_epic_move_list:limit_epic_board_moves_by_user_log:log')
          end
        end
      end
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_epic do
      let_it_be(:user) { create(:user, developer_of: group) }

      let(:boundary_object) { group }
      let(:mutation) { graphql_mutation(mutation_name, params.merge(move_params), 'clientMutationId errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end

    context 'when the epic belongs to a subgroup of the board group' do
      let_it_be(:subgroup) { create(:group, parent: group) }

      let(:epic) { create(:epic, group: subgroup) }

      it_behaves_like 'authorizing granular token permissions for GraphQL', :update_epic do
        let_it_be(:user) { create(:user, developer_of: group) }

        let(:boundary_object) { subgroup }
        let(:mutation) { graphql_mutation(mutation_name, params.merge(move_params), 'clientMutationId errors') }
        let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
      end
    end
  end

  def mutation(additional_params = {})
    graphql_mutation(mutation_name, move_params.merge(additional_params),
      <<-QL.strip_heredoc
        clientMutationId
        epic {
          iid,
          relativePosition
          labels {
            nodes {
              title
            }
          }
        }
        errors
    QL
    )
  end
end
