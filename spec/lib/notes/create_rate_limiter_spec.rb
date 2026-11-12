# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Notes::CreateRateLimiter, :freeze_time, :clean_gitlab_redis_rate_limiting,
  feature_category: :team_planning do
  let_it_be(:user) { create(:user) }
  let_it_be(:other_user) { create(:user) }
  let_it_be(:support_bot) { create(:support_bot) }
  let_it_be(:project) { create(:project) }

  before do
    stub_application_setting(notes_create_limit: 1)
  end

  describe '#throttled?' do
    def throttled?(author: user, external_author: nil)
      described_class.new(author: author, project: project, external_author: external_author).throttled?
    end

    context 'without an external author' do
      it 'is throttled once the user exceeds the limit' do
        expect(throttled?).to be(false)
        expect(throttled?).to be(true)
      end

      it 'counts each user separately' do
        throttled?

        expect(throttled?(author: other_user)).to be(false)
      end

      it 'shares the notes_create counter with the web and API entry points' do
        Gitlab::ApplicationRateLimiter.throttled?(:notes_create, scope: { user: user })

        expect(throttled?).to be(true)
      end

      it 'logs the throttled note' do
        throttled?

        expect(Gitlab::AuthLogger).to receive(:error).with(
          message: 'Application_Rate_Limiter_Request',
          env: :notes_create_request_limit,
          Labkit::Fields::GL_USER_ID => user.id,
          Labkit::Fields::GL_USER_NAME => user.username,
          Labkit::Fields::GL_PROJECT_ID => project.id
        )

        throttled?
      end

      context 'when the note has no project' do
        it 'is throttled per user and logs without a project' do
          rate_limiter = described_class.new(author: user, project: nil)

          expect(rate_limiter.throttled?).to be(false)

          expect(Gitlab::AuthLogger).to receive(:error).with(
            a_hash_including(Labkit::Fields::GL_USER_ID => user.id, Labkit::Fields::GL_PROJECT_ID => nil)
          )

          expect(rate_limiter.throttled?).to be(true)
        end
      end

      context 'when the user is in the allowlist' do
        before do
          stub_application_setting(notes_create_limit_allowlist: [user.username])
        end

        it 'is not throttled' do
          expect(throttled?).to be(false)
          expect(throttled?).to be(false)
        end
      end
    end

    context 'with an external author' do
      let(:sender) { 'sender@example.com' }

      it 'is throttled once the sender exceeds the limit' do
        expect(throttled?(author: support_bot, external_author: sender)).to be(false)
        expect(throttled?(author: support_bot, external_author: sender)).to be(true)
      end

      it 'counts each sender separately' do
        throttled?(author: support_bot, external_author: sender)

        expect(throttled?(author: support_bot, external_author: 'other@example.com')).to be(false)
      end

      it 'ignores the case of the sender address' do
        throttled?(author: support_bot, external_author: sender)

        expect(throttled?(author: support_bot, external_author: sender.upcase)).to be(true)
      end

      it 'does not count against the support bot user' do
        2.times { throttled?(author: support_bot, external_author: sender) }

        expect(Gitlab::ApplicationRateLimiter.throttled?(:notes_create, scope: { user: support_bot })).to be(false)
      end

      it 'counts mail without a sender per project' do
        expect(throttled?(author: support_bot)).to be(false)
        expect(throttled?(author: support_bot)).to be(true)

        expect(Gitlab::ApplicationRateLimiter.throttled?(:notes_create, scope: { user: support_bot })).to be(false)
      end

      it 'logs the throttled note' do
        throttled?(author: support_bot, external_author: sender)

        expect(Gitlab::AuthLogger).to receive(:error).with(
          message: 'Application_Rate_Limiter_Request',
          env: :notes_create_by_external_author_request_limit,
          Labkit::Fields::GL_USER_ID => support_bot.id,
          Labkit::Fields::GL_USER_NAME => support_bot.username,
          Labkit::Fields::GL_PROJECT_ID => project.id
        )

        throttled?(author: support_bot, external_author: sender)
      end
    end

    context 'when the limit is 0' do
      before do
        stub_application_setting(notes_create_limit: 0)
      end

      it 'is not throttled' do
        expect(throttled?).to be(false)
        expect(throttled?).to be(false)
      end
    end

    context 'when notes_create_rate_limit_email_and_chat is disabled' do
      before do
        stub_feature_flags(notes_create_rate_limit_email_and_chat: false)
      end

      it 'is not throttled and does not count the note' do
        expect(throttled?).to be(false)
        expect(throttled?).to be(false)

        expect(Gitlab::ApplicationRateLimiter.throttled?(:notes_create, scope: { user: user })).to be(false)
      end
    end
  end
end
