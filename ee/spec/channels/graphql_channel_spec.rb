# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GraphqlChannel, feature_category: :api do
  let_it_be(:merge_request) { create(:merge_request) }
  let_it_be(:user) { create(:user, developer_of: merge_request.project) }
  let_it_be(:read_api_token) { create(:personal_access_token, scopes: ['read_api'], user: user) }
  let_it_be(:read_user_token) { create(:personal_access_token, scopes: ['read_user'], user: user) }
  let_it_be(:ai_features_token) { create(:personal_access_token, scopes: ['ai_features'], user: user) }
  let_it_be(:read_api_and_read_user_token) do
    create(:personal_access_token, scopes: %w[read_user read_api], user: user)
  end

  describe '#subscribed' do
    let(:query) do
      <<~GRAPHQL
      subscription mergeRequestReviewersUpdated($issuableId: IssuableID!) {
        mergeRequestReviewersUpdated(issuableId: $issuableId) {
          ... on MergeRequest { id title }
        }
      }
      GRAPHQL
    end

    let(:query_variables) { { issuableId: merge_request.to_global_id } }

    let(:subscribe_params) do
      {
        query: query,
        variables: query_variables
      }
    end

    before do
      stub_action_cable_connection current_user: user
    end

    context 'with a personal access token' do
      before do
        stub_action_cable_connection current_user: user, access_token: access_token
      end

      context 'with an api scoped personal access token' do
        let(:access_token) { read_api_token }

        it 'subscribes to the given graphql subscription' do
          subscribe(subscribe_params)

          expect(subscription).to be_confirmed
          expect(subscription.streams).to include(/graphql-event::mergeRequestReviewersUpdated:issuableId/)
        end
      end

      context 'with an ai_features personal access token' do
        let(:access_token) { ai_features_token }

        it 'confirms the subscription but gets no stream' do
          subscribe(subscribe_params)

          expect(subscription).to be_confirmed
          expect(subscription.streams).not_to include(/graphql-event::mergeRequestReviewersUpdated:issuableId/)
        end

        context 'with a graphql subscription that allows ai_features' do
          let(:query) do
            <<~GRAPHQL
            subscription aiCompletionResponse(
              $userId: UserID
              $clientSubscriptionId: String
              $aiAction: AiAction
            ) {
              aiCompletionResponse(
                userId: $userId
                aiAction: $aiAction
                clientSubscriptionId: $clientSubscriptionId
              ) {
                id
                requestId
                content
                errors
                role
                timestamp
                type
                chunkId
                extras {
                  sources
                }
              }
            }
            GRAPHQL
          end

          let(:query_variables) { { userId: user.to_global_id, aiAction: 'CHAT', clientSubscriptionId: 'abc123' } }

          it 'confirms the subscription and gets a stream' do
            subscribe(subscribe_params)

            expect(subscription).to be_confirmed
            expect(subscription.streams).to include(
              /graphql-event::aiCompletionResponse:aiAction:chat:clientSubscriptionId:abc123/
            )
          end
        end
      end
    end

    context 'with the aiDuoWorkflowCreate mutation' do
      let(:query) do
        <<~GRAPHQL
        mutation {
          aiDuoWorkflowCreate(input: { goal: "hi", workflowDefinition: "chat", environment: WEB }) {
            errors
          }
        }
        GRAPHQL
      end

      let(:query_variables) { {} }

      it 'checks the AI users per IP limit with the connection request' do
        expect(Ai::UsersPerIpLimit).to receive(:new)
          .with(user: user, request: connection.request).and_call_original

        subscribe(subscribe_params)
      end

      context 'when the AI users per IP limit is exceeded' do
        before do
          allow_next_instance_of(Ai::UsersPerIpLimit) do |limit|
            allow(limit).to receive(:throttled?).and_return(true)
          end
        end

        it 'returns the throttled error' do
          subscribe(subscribe_params)

          expect(transmissions.last.dig('result', 'errors')).to include(
            a_hash_including('message' => Gitlab::ApplicationRateLimiter.throttled_error_message)
          )
        end
      end
    end
  end
end
