# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::ProjectAuthorizations::BlockedUserRefreshSkip, feature_category: :permissions do
  using RSpec::Parameterized::TableSyntax

  before do
    allow(Gitlab::AppJsonLogger).to receive(:info).and_call_original
  end

  def skipped_log_entry(**fields)
    hash_including(
      event: 'authorized_projects_refresh_skipped',
      'authorized_projects_refresh.skip_reason': 'user_blocked',
      **fields
    )
  end

  describe '.skip_and_log?' do
    subject(:skip_and_log) { described_class.skip_and_log?(user, skipped_in: :user_refresh) }

    where(:traits, :skipped) do
      [:blocked]                   | true
      [:ldap_blocked]              | true
      [:blocked_pending_approval]  | true
      [:banned]                    | true
      [:deactivated]               | false
      []                           | false
      [:project_bot, :blocked]     | false
      [:service_account, :blocked] | false
    end

    with_them do
      let(:user) { create(:user, *traits) }

      it { is_expected.to be(skipped) }
    end

    context 'when skip_authorization_refresh_for_blocked_users is disabled' do
      let(:user) { create(:user, :blocked) }

      before do
        stub_feature_flags(skip_authorization_refresh_for_blocked_users: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when resolve_project_access_from_memberships is disabled' do
      let(:user) { create(:user, :blocked) }

      before do
        stub_feature_flags(resolve_project_access_from_memberships: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the user is being deleted' do
      let(:user) { create(:user, :blocked) }

      before do
        UserCustomAttribute.set_deletion_started_at(user)
      end

      it { is_expected.to be(false) }
    end

    context 'when the user is blocked' do
      let(:user) { create(:user, :blocked) }

      it 'skips the refresh and logs it against the code path' do
        expect(Gitlab::AppJsonLogger).to receive(:info).with(skipped_log_entry(
          'authorized_projects_refresh.skipped_in': 'user_refresh',
          'authorized_projects_refresh.skipped_users_count': 1
        ))

        expect(skip_and_log).to be(true)
      end
    end

    context 'when the user is active' do
      let(:user) { create(:user) }

      it 'does not skip the refresh' do
        expect(Gitlab::AppJsonLogger).not_to receive(:info).with(skipped_log_entry)

        expect(skip_and_log).to be(false)
      end
    end
  end

  describe '.skipped_user_ids' do
    subject(:skipped_user_ids) { described_class.skipped_user_ids(user_ids, skipped_in: :project_recalculate) }

    let_it_be(:blocked_user) { create(:user, :blocked) }
    let_it_be(:banned_user) { create(:user, :banned) }
    let_it_be(:active_user) { create(:user) }
    let_it_be(:deactivated_user) { create(:user, :deactivated) }
    let_it_be(:blocked_bot) { create(:user, :project_bot, :blocked) }
    let_it_be(:user_being_deleted) { create(:user, :blocked) }

    let(:user_ids) do
      [blocked_user, banned_user, active_user, deactivated_user, blocked_bot, user_being_deleted].map(&:id) +
        [non_existing_record_id]
    end

    before_all do
      UserCustomAttribute.set_deletion_started_at(user_being_deleted)
    end

    it 'returns the blocked humans and logs their count against the code path in one line' do
      expect(Gitlab::AppJsonLogger).to receive(:info).with(
        event: 'authorized_projects_refresh_skipped',
        'authorized_projects_refresh.skip_reason': 'user_blocked',
        'authorized_projects_refresh.skipped_in': 'project_recalculate',
        'authorized_projects_refresh.skipped_users_count': 2
      ).once

      expect(skipped_user_ids).to contain_exactly(blocked_user.id, banned_user.id)
    end

    it 'looks up only user IDs in batches and deletion marks only for the blocked ones' do
      stub_const("#{described_class}::BATCH_SIZE", 2)

      recorder = ActiveRecord::QueryRecorder.new { skipped_user_ids }

      expect(recorder.log.grep(/FROM "users"/)).to all(start_with('SELECT "users"."id" FROM "users"'))
      expect(recorder.log.grep(/FROM "users"/).size).to eq(4)
      expect(recorder.log.grep(/FROM "user_custom_attributes"/).size).to eq(2)
    end

    context 'when no IDs are given' do
      let(:user_ids) { [] }

      it 'does not query users' do
        expect(Gitlab::AppJsonLogger).not_to receive(:info).with(skipped_log_entry)

        recorder = ActiveRecord::QueryRecorder.new do
          expect(skipped_user_ids).to be_empty
        end

        expect(recorder.count).to eq(0)
      end
    end

    context 'when skip_authorization_refresh_for_blocked_users is enabled for one user' do
      before do
        stub_feature_flags(skip_authorization_refresh_for_blocked_users: banned_user)
      end

      it 'returns only that user' do
        expect(skipped_user_ids).to contain_exactly(banned_user.id)
      end
    end

    context 'when resolve_project_access_from_memberships is enabled for one user' do
      before do
        stub_feature_flags(resolve_project_access_from_memberships: banned_user)
      end

      it 'returns only that user' do
        expect(skipped_user_ids).to contain_exactly(banned_user.id)
      end
    end

    context 'when skip_authorization_refresh_for_blocked_users is disabled' do
      before do
        stub_feature_flags(skip_authorization_refresh_for_blocked_users: false)
      end

      it 'returns no users without querying' do
        expect(Gitlab::AppJsonLogger).not_to receive(:info).with(skipped_log_entry)

        recorder = ActiveRecord::QueryRecorder.new do
          expect(skipped_user_ids).to be_empty
        end

        expect(recorder.count).to eq(0)
      end
    end
  end

  describe '.skipped_user_ids_among' do
    subject(:skipped_user_ids_among) do
      described_class.skipped_user_ids_among(users, skipped_in: :safety_net_check)
    end

    let_it_be(:blocked_user) { create(:user, :blocked) }
    let_it_be(:active_user) { create(:user) }
    let_it_be(:blocked_bot) { create(:user, :project_bot, :blocked) }
    let_it_be(:user_being_deleted) { create(:user, :blocked) }

    let(:users) { [blocked_user, active_user, blocked_bot, user_being_deleted] }

    before_all do
      UserCustomAttribute.set_deletion_started_at(user_being_deleted)
    end

    it 'returns the blocked humans and logs them against the code path in one line' do
      expect(Gitlab::AppJsonLogger).to receive(:info).with(skipped_log_entry(
        'authorized_projects_refresh.skipped_in': 'safety_net_check',
        'authorized_projects_refresh.skipped_users_count': 1
      )).once

      expect(skipped_user_ids_among).to contain_exactly(blocked_user.id)
    end

    it 'reads the state from the users and looks up deletion marks once' do
      recorder = ActiveRecord::QueryRecorder.new { skipped_user_ids_among }

      expect(recorder.log.grep(/FROM "users"/)).to be_empty
      expect(recorder.log.grep(/FROM "user_custom_attributes"/).size).to eq(1)
    end

    context 'when no user is blocked' do
      let(:users) { [active_user, blocked_bot] }

      it 'does not query or log' do
        expect(Gitlab::AppJsonLogger).not_to receive(:info).with(skipped_log_entry)

        recorder = ActiveRecord::QueryRecorder.new do
          expect(skipped_user_ids_among).to be_empty
        end

        expect(recorder.count).to eq(0)
      end
    end

    context 'when skip_authorization_refresh_for_blocked_users is disabled' do
      before do
        stub_feature_flags(skip_authorization_refresh_for_blocked_users: false)
      end

      it 'returns no users without querying' do
        recorder = ActiveRecord::QueryRecorder.new do
          expect(skipped_user_ids_among).to be_empty
        end

        expect(recorder.count).to eq(0)
      end
    end
  end

  describe 'removing a blocked user from a group', :sidekiq_inline do
    let(:group) { create(:group) }
    let!(:project) { create(:project, group: group) }
    let(:user) { create(:user) }

    before do
      group.add_developer(user)
    end

    it 'keeps the authorization while the user is blocked and removes it once they are active again' do
      user.block!
      group.members.find_by(user: user).destroy!

      expect(user.project_authorizations.pluck(:project_id)).to contain_exactly(project.id)

      user.activate!

      expect(user.project_authorizations.reload).to be_empty
    end
  end
end
