# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NotificationRecipients::Builder::Default, feature_category: :team_planning do
  describe '#notification_recipients' do
    let_it_be(:group) { create(:group, :public) }
    let_it_be(:project) { create(:project, :public, group: group) }
    let_it_be(:target) { create(:issue, project: project) }
    let_it_be(:current_user) { create(:user) }
    let_it_be(:watcher) { create(:user) }
    let_it_be(:subscriber) { create(:user) }

    let(:builder) { described_class.new(target, current_user, action: :new) }

    before_all do
      create(:notification_setting, source: project, user: watcher, level: :watch)
      create(:subscription, project: project, user: subscriber, subscribable: target, subscribed: true)
    end

    # The first build saves a global setting for recipients that have none.
    before do
      build_recipients
    end

    def build_recipients
      described_class.new(target, current_user, action: :new).notification_recipients
    end

    def instantiated_notification_settings
      count = 0
      callback = ->(*, payload) { count += payload[:record_count] if payload[:class_name] == 'NotificationSetting' }

      ActiveSupport::Notifications.subscribed(callback, 'instantiation.active_record') { build_recipients }

      count
    end

    def create_unrelated_settings
      [watcher, subscriber].each do |user|
        create(:notification_setting, source: create(:group), user: user, level: :watch)
      end
    end

    it 'loads only the settings for the project, its groups and the global level', :aggregate_failures do
      control = instantiated_notification_settings

      create_unrelated_settings

      expect(instantiated_notification_settings).to eq(control)
      expect(builder.notification_recipients.map(&:user)).to include(watcher, subscriber)
    end

    it 'does not run a notification settings query per recipient', :request_store, :use_sql_query_cache do
      control = ActiveRecord::QueryRecorder.new(skip_cached: false) { build_recipients }

      create(:notification_setting, source: project, user: create(:user), level: :watch)

      expect { build_recipients }.to issue_same_number_of_queries_as(control)
    end

    it 'leaves the notification settings of every candidate unloaded, including filtered-out ones' do
      # The acting user is filtered out as their own activity.
      create(:notification_setting, source: project, user: current_user, level: :watch)
      candidates = []
      allow(builder).to receive(:make_recipient).and_wrap_original do |method, user, *args|
        candidates << user
        method.call(user, *args)
      end

      builder.notification_recipients

      expect(candidates.map(&:id)).to include(current_user.id, watcher.id, subscriber.id)
      expect(candidates).to all(satisfy { |user| !user.association(:notification_settings).loaded? })
    end

    context 'when notification_recipients_scoped_settings_preload is disabled' do
      before do
        stub_feature_flags(notification_recipients_scoped_settings_preload: false)
      end

      it 'loads every setting of each recipient', :aggregate_failures do
        control = instantiated_notification_settings

        create_unrelated_settings

        expect(instantiated_notification_settings).to eq(control + 2)
        expect(builder.notification_recipients.map(&:user)).to include(watcher, subscriber)
      end
    end
  end

  describe '#build!' do
    let_it_be(:group)   { create(:group, :public) }
    let_it_be(:project) { create(:project, :public, group: group, developers: project_watcher) }
    let_it_be(:target)  { create(:issue, project: project) }

    let_it_be(:current_user)    { create(:user) }
    let_it_be(:other_user)      { create(:user) }
    let_it_be(:participant)     { create(:user) }
    let_it_be(:group_watcher)   { create(:user) }
    let_it_be(:project_watcher) { create(:user) }

    let_it_be(:notification_setting_project_w) do
      create(:notification_setting, source: project, user: project_watcher, level: 2)
    end

    let_it_be(:notification_setting_group_w) do
      create(:notification_setting, source: group, user: group_watcher, level: 2)
    end

    subject do
      described_class.new(target, current_user, action: :new).tap(&:build!)
        .recipients.map(&:user)
    end

    describe 'participants and project watchers' do
      before do
        allow(target).to receive(:participants).and_return([participant, current_user])
      end

      it { is_expected.to include(participant, project_watcher, group_watcher) }
      it { is_expected.not_to include(other_user) }
    end

    describe 'subscribers' do
      it 'adds all subscribers' do
        subscriber = create(:user)
        non_subscriber = create(:user)
        create(:subscription, project: project, user: subscriber, subscribable: target, subscribed: true)
        create(:subscription, project: project, user: non_subscriber, subscribable: target, subscribed: false)

        is_expected.to include(subscriber)
      end
    end

    describe 'custom notifications' do
      let_it_be(:custom_notification_user) { create(:user) }
      let_it_be(:another_group)   { create(:group) }
      let_it_be(:another_project) { create(:project, namespace: another_group) }

      context 'with project custom notification setting' do
        before do
          create(:notification_setting, source: project, user: custom_notification_user, level: :custom)
        end

        it { is_expected.to include(custom_notification_user) }
      end

      context 'with the project custom notification setting in another project' do
        before do
          create(:notification_setting, source: another_project, user: custom_notification_user, level: :custom)
        end

        it { is_expected.not_to include(custom_notification_user) }
      end

      context 'with group custom notification setting' do
        before do
          create(:notification_setting, source: group, user: custom_notification_user, level: :custom)
        end

        it { is_expected.to include(custom_notification_user) }
      end

      context 'with the group custom notification setting in another group' do
        before do
          create(:notification_setting, source: another_group, user: custom_notification_user, level: :custom)
        end

        it { is_expected.not_to include(custom_notification_user) }
      end

      context 'with project global custom notification setting' do
        before do
          create(:notification_setting, source: project, user: custom_notification_user, level: :global)
        end

        context 'with global custom notification setting' do
          before do
            create(:notification_setting, source: nil, user: custom_notification_user, level: :custom)
          end

          it { is_expected.to include(custom_notification_user) }
        end

        context 'without global custom notification setting' do
          it { is_expected.not_to include(custom_notification_user) }
        end
      end

      context 'with group global custom notification setting' do
        before do
          create(:notification_setting, source: group, user: custom_notification_user, level: :global)
        end

        context 'with global custom notification setting' do
          before do
            create(:notification_setting, source: nil, user: custom_notification_user, level: :custom)
          end

          it { is_expected.to include(custom_notification_user) }
        end

        context 'without global custom notification setting' do
          it { is_expected.not_to include(custom_notification_user) }
        end
      end

      context 'with group custom notification setting in deeply nested parent group' do
        let(:grand_parent_group) { create(:group, :public) }
        let(:parent_group) { create(:group, :public, parent: grand_parent_group) }
        let(:group) { create(:group, :public, parent: parent_group) }
        let(:project) { create(:project, :public, group: group, developers: project_watcher) }
        let(:target) { create(:issue, project: project) }

        before do
          create(:notification_setting, source: grand_parent_group, user: custom_notification_user, level: :custom)
        end

        it { is_expected.to include(custom_notification_user) }
      end

      context 'without a project or group' do
        let(:target) { create(:project_snippet) }

        before do
          create(:notification_setting, source: nil, user: custom_notification_user, level: :custom)
        end

        it { is_expected.not_to include(custom_notification_user) }
      end

      context 'when target is a work item' do
        before_all do
          create(
            :notification_setting,
            source: project,
            user: custom_notification_user,
            level: :custom,
            new_issue: true,
            reopen_issue: true,
            close_issue: true,
            reassign_issue: true,
            issue_due: true
          )
        end

        subject do
          described_class.new(target, current_user, action: action).tap(&:build!)
            .notification_recipients.map(&:user)
        end

        context 'when work item is an issue' do
          let_it_be(:target) { create(:work_item, :issue, project: project) }

          where(:action) do
            %w[new reopen close reassign]
          end

          with_them do
            it { is_expected.to include(custom_notification_user) }
          end
        end

        context 'when work item issue is due' do
          subject do
            described_class.new(target, current_user, action: :due, custom_action: :issue_due).tap(&:build!)
              .notification_recipients.map(&:user)
          end

          it { is_expected.to include(custom_notification_user) }
        end

        context 'when work item is task' do
          let_it_be(:target) { create(:work_item, :task, project: project) }

          where(:action) do
            %w[new reopen close reassign]
          end

          with_them do
            it { is_expected.to include(custom_notification_user) }
          end

          context 'when work item task is due' do
            subject do
              described_class.new(target, current_user, action: :due, custom_action: :issue_due).tap(&:build!)
                .notification_recipients.map(&:user)
            end

            it { is_expected.to include(custom_notification_user) }
          end
        end
      end
    end
  end
end
