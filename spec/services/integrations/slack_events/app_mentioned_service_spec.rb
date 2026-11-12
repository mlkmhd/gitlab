# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackEvents::AppMentionedService, feature_category: :integrations do
  describe '#execute' do
    let_it_be(:slack_installation) { create(:slack_integration) }
    let_it_be(:user) { create(:user) }
    let_it_be(:chat_name) do
      create(:chat_name, user: user, team_id: slack_installation.team_id, chat_id: 'U0123ABCDEF')
    end

    let(:slack_workspace_id) { slack_installation.team_id }
    let(:slack_user_id) { chat_name.chat_id }
    let(:channel_id) { 'C0123ABCDEF' }
    let(:message_ts) { '1234567890.123456' }
    let(:event_text) { "<@#{slack_installation.bot_user_id}> hello world" }

    let(:params) do
      {
        team_id: slack_workspace_id,
        is_ext_shared_channel: false,
        event: {
          user: slack_user_id,
          channel: channel_id,
          ts: message_ts,
          text: event_text
        }
      }
    end

    let(:reactions_add_url) { "#{Slack::API::BASE_URL}/reactions.add" }
    let(:post_message_url) { "#{Slack::API::BASE_URL}/chat.postMessage" }
    let(:post_ephemeral_url) { "#{Slack::API::BASE_URL}/chat.postEphemeral" }
    let(:conversations_replies_url) { "#{Slack::API::BASE_URL}/conversations.replies" }

    subject(:execute) { described_class.new(params).execute }

    shared_examples 'does not call Slack API' do
      it 'returns success without calling the Slack API' do
        expect(Gitlab::HTTP).not_to receive(:post)
        expect(Gitlab::HTTP).not_to receive(:get)

        is_expected.to be_success
      end
    end

    context 'when event data is missing' do
      context 'when workspace id is missing' do
        let(:params) { { event: { user: slack_user_id, channel: channel_id, ts: message_ts } } }

        it { is_expected.to be_error }
      end

      context 'when user id is missing' do
        let(:params) { { team_id: slack_workspace_id, event: { channel: channel_id, ts: message_ts } } }

        it { is_expected.to be_error }
      end

      context 'when channel is missing' do
        let(:params) { { team_id: slack_workspace_id, event: { user: slack_user_id, ts: message_ts } } }

        it { is_expected.to be_error }
      end
    end

    context 'when slack installation cannot be found' do
      let(:slack_workspace_id) { 'UNKNOWN_WORKSPACE' }

      it_behaves_like 'does not call Slack API'

      it 'does not track any internal events' do
        expect { execute }.to not_trigger_internal_events('receive_slack_duo_mention', 'block_slack_duo_mention')
      end
    end

    describe 'channels shared with external organizations' do
      using RSpec::Parameterized::TableSyntax

      let(:external_channel_text) { 'GitLab Duo is not available in channels shared with external organizations.' }

      before do
        stub_request(:post, reactions_add_url).to_return(status: 200, body: { ok: true }.to_json,
          headers: { 'Content-Type' => 'application/json' })
        stub_request(:post, post_ephemeral_url).to_return(status: 200, body: { ok: true }.to_json,
          headers: { 'Content-Type' => 'application/json' })
      end

      where(:case_name, :envelope, :channel_type) do
        'Slack marks the channel as shared'   | { is_ext_shared_channel: true }    | nil
        'Slack marks a 1:1 DM as shared'      | { is_ext_shared_channel: true }    | 'im'
        'Slack omits the flag in a channel'   | {}                                 | nil
        'Slack omits the flag in a group DM'  | {}                                 | 'mpim'
        'Slack omits the flag in a 1:1 DM'    | {}                                 | 'im'
        'the flag is not a boolean'           | { is_ext_shared_channel: 'false' } | nil
      end

      with_them do
        let(:params) do
          {
            team_id: slack_workspace_id,
            event: { user: slack_user_id, channel: channel_id, channel_type: channel_type, ts: message_ts }.compact
          }.merge(envelope)
        end

        it 'refuses the mention without looking up the Slack user', :aggregate_failures do
          expect(ChatNames::FindUserService).not_to receive(:new)
          expect(ChatNames::AuthorizeUserService).not_to receive(:new)

          is_expected.to be_success

          expect(WebMock).to have_requested(:post, reactions_add_url).with(
            body: hash_including('name' => 'lock', 'channel' => channel_id, 'timestamp' => message_ts)
          )
          expect(WebMock).to have_requested(:post, post_ephemeral_url).with(
            body: hash_including('user' => slack_user_id, 'text' => a_string_including(external_channel_text))
          )
        end

        it 'tracks the blocked mention without a user' do
          expect { execute }
            .to trigger_internal_events('receive_slack_duo_mention').with(user: nil)
            .and trigger_internal_events('block_slack_duo_mention').with(
              user: nil, additional_properties: { property: 'externally_shared_channel' }
            )
        end
      end

      context 'when Slack marks the channel as not shared' do
        let(:slack_user_id) { 'U_UNLINKED' }

        it 'continues to the account-linking prompt' do
          is_expected.to be_success

          expect(WebMock).to have_requested(:post, post_ephemeral_url).with(
            body: hash_including('text' => a_string_including('mention me again'))
          )
          expect(WebMock).not_to have_requested(:post, post_ephemeral_url).with(
            body: hash_including('text' => a_string_including(external_channel_text))
          )
        end
      end
    end

    context 'when user is not authenticated' do
      let(:slack_user_id) { 'U_UNLINKED' }

      before do
        stub_request(:post, reactions_add_url).to_return(status: 200, body: { ok: true }.to_json,
          headers: { 'Content-Type' => 'application/json' })
        stub_request(:post, post_ephemeral_url).to_return(status: 200, body: { ok: true }.to_json,
          headers: { 'Content-Type' => 'application/json' })
      end

      it 'adds lock reaction and posts ephemeral auth message' do
        is_expected.to be_success

        expect(WebMock).to have_requested(:post, reactions_add_url).with(
          body: hash_including('name' => 'lock', 'channel' => channel_id, 'timestamp' => message_ts)
        )
        expect(WebMock).to have_requested(:post, post_ephemeral_url).with(
          body: hash_including(
            'channel' => channel_id,
            'user' => slack_user_id,
            'text' => a_string_including('mention me again')
          )
        )
      end

      it 'tracks the received mention and the blocked mention without a user' do
        expect { execute }
          .to trigger_internal_events('receive_slack_duo_mention').with(user: nil)
          .and trigger_internal_events('block_slack_duo_mention').with(
            user: nil, additional_properties: { property: 'user_not_linked' }
          )
      end

      context 'when authorize URL is nil' do
        before do
          allow_next_instance_of(ChatNames::AuthorizeUserService) do |service|
            allow(service).to receive(:execute).and_return(nil)
          end
        end

        it 'does not post an ephemeral message' do
          is_expected.to be_success

          expect(WebMock).not_to have_requested(:post, post_ephemeral_url)
        end
      end

      context 'when team_domain is provided in params' do
        let(:params) do
          {
            team_id: slack_workspace_id,
            is_ext_shared_channel: false,
            team_domain: 'my-team-domain',
            event: {
              user: slack_user_id,
              channel: channel_id,
              ts: message_ts,
              text: event_text
            }
          }
        end

        it 'uses team_domain from params in authorize_params' do
          is_expected.to be_success

          expect(WebMock).to have_requested(:post, post_ephemeral_url)
        end
      end

      context 'when ensure_user_linked raises an HTTP error' do
        before do
          allow_next_instance_of(ChatNames::AuthorizeUserService) do |service|
            allow(service).to receive(:execute).and_raise(Errno::ECONNREFUSED, 'error')
          end
        end

        it 'tracks the exception' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception)
            .with(instance_of(Errno::ECONNREFUSED), slack_workspace_id: slack_workspace_id)

          is_expected.to be_success
        end
      end

      context 'when reactions.add returns an error response' do
        before do
          stub_request(:post, reactions_add_url).to_return(
            status: 200,
            body: { ok: false, error: 'already_reacted' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
        end

        it 'logs the Slack API error' do
          expect(Gitlab::IntegrationsLogger).to receive(:error).with(
            hash_including(message: 'Slack API error when adding reaction')
          )

          is_expected.to be_success
        end
      end

      context 'when post_ephemeral returns an error response' do
        before do
          stub_request(:post, post_ephemeral_url).to_return(
            status: 200,
            body: { ok: false, error: 'user_not_in_channel' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
        end

        it 'logs the Slack API error' do
          expect(Gitlab::IntegrationsLogger).to receive(:error).with(
            hash_including(message: 'Slack API error when posting ephemeral message')
          )

          is_expected.to be_success
        end
      end

      context 'when post_ephemeral raises an HTTP error' do
        before do
          stub_request(:post, reactions_add_url).to_return(
            status: 200, body: { ok: true }.to_json, headers: { 'Content-Type' => 'application/json' })
          stub_request(:post, post_ephemeral_url).to_raise(Errno::ECONNREFUSED.new('error'))
        end

        it 'logs the error via Slack::API and does not raise' do
          expect(Gitlab::IntegrationsLogger).to receive(:error).with(
            hash_including(message: 'Slack API error when posting ephemeral message')
          )

          is_expected.to be_success
        end
      end
    end

    context 'when user is authenticated' do
      context 'when user cannot use slash commands' do
        let_it_be(:blocked_user) { create(:user, :blocked) }
        let_it_be(:blocked_chat_name) do
          create(:chat_name, user: blocked_user, team_id: slack_installation.team_id, chat_id: 'U_BLOCKED')
        end

        let(:slack_user_id) { blocked_chat_name.chat_id }

        it 'returns success without calling Slack API' do
          is_expected.to be_success

          expect(WebMock).not_to have_requested(:post, reactions_add_url)
        end

        it 'tracks the blocked mention with the permission reason' do
          expect { execute }
            .to trigger_internal_events('receive_slack_duo_mention').with(user: blocked_user)
            .and trigger_internal_events('block_slack_duo_mention').with(
              user: blocked_user, additional_properties: { property: 'no_permission' }
            )
        end
      end

      context 'without GitLab Duo (FOSS)', unless: Gitlab.ee? do
        before do
          stub_request(:post, reactions_add_url).to_return(status: 200, body: { ok: true }.to_json,
            headers: { 'Content-Type' => 'application/json' })
          stub_request(:post, post_ephemeral_url).to_return(status: 200, body: { ok: true }.to_json,
            headers: { 'Content-Type' => 'application/json' })
        end

        it 'adds lock reaction and posts ephemeral experiment features message' do
          is_expected.to be_success

          expect(WebMock).to have_requested(:post, reactions_add_url).with(
            body: hash_including('name' => 'lock', 'channel' => channel_id, 'timestamp' => message_ts)
          )
          expect(WebMock).to have_requested(:post, post_ephemeral_url).with(
            body: hash_including(
              'channel' => channel_id,
              'user' => slack_user_id,
              'text' => a_string_including(
                'This feature requires experiment and beta GitLab Duo features to be turned on.'
              )
            )
          )
        end

        it 'tracks the blocked mention with the experiment features reason' do
          expect { execute }.to trigger_internal_events('block_slack_duo_mention').with(
            user: user, additional_properties: { property: 'experiment_features_disabled' }
          )
        end
      end

      context 'when the mention is inside a thread' do
        let(:thread_ts) { '1234567890.000001' }

        let(:params) do
          {
            team_id: slack_workspace_id,
            is_ext_shared_channel: false,
            event: {
              user: slack_user_id,
              channel: channel_id,
              ts: message_ts,
              thread_ts: thread_ts,
              text: event_text
            }
          }
        end

        context 'when user is not authenticated' do
          let(:slack_user_id) { 'U_UNLINKED' }

          before do
            stub_request(:post, reactions_add_url).to_return(status: 200, body: { ok: true }.to_json,
              headers: { 'Content-Type' => 'application/json' })
            stub_request(:post, post_ephemeral_url).to_return(status: 200, body: { ok: true }.to_json,
              headers: { 'Content-Type' => 'application/json' })
          end

          it 'posts the ephemeral auth message inside the thread' do
            is_expected.to be_success

            expect(WebMock).to have_requested(:post, post_ephemeral_url).with(
              body: hash_including('thread_ts' => thread_ts)
            )
          end
        end

        context 'when experiment and beta Duo features are turned off' do
          before do
            stub_request(:post, reactions_add_url).to_return(status: 200, body: { ok: true }.to_json,
              headers: { 'Content-Type' => 'application/json' })
            stub_request(:post, post_ephemeral_url).to_return(status: 200, body: { ok: true }.to_json,
              headers: { 'Content-Type' => 'application/json' })
          end

          it 'posts the ephemeral no-access message inside the thread' do
            is_expected.to be_success

            expect(WebMock).to have_requested(:post, post_ephemeral_url).with(
              body: hash_including('thread_ts' => thread_ts)
            )
          end
        end
      end

      context 'when the mention is at the channel root (no thread)' do
        context 'when user is not authenticated' do
          let(:slack_user_id) { 'U_UNLINKED' }

          before do
            stub_request(:post, reactions_add_url).to_return(status: 200, body: { ok: true }.to_json,
              headers: { 'Content-Type' => 'application/json' })
            stub_request(:post, post_ephemeral_url).to_return(status: 200, body: { ok: true }.to_json,
              headers: { 'Content-Type' => 'application/json' })
          end

          it 'posts the ephemeral auth message at the channel root (no thread_ts)' do
            is_expected.to be_success

            expect(WebMock).to have_requested(:post, post_ephemeral_url).with(
              body: ->(body) { !Gitlab::Json::SafeParser.parse(body).key?('thread_ts') }
            )
          end
        end
      end
    end
  end
end
