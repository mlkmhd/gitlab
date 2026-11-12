# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::ImportExport::MembersMapper, feature_category: :importers do
  describe '#map' do
    let(:user) { create(:admin) }
    let(:original_member) { create(:user) }
    let(:exported_members) do
      [{
        "id" => 2,
        "access_level" => 40,
        "source_id" => 14,
        "source_type" => "Project",
        "notification_level" => 3,
        "created_at" => "2016-03-11T10:21:44.822Z",
        "updated_at" => "2016-03-11T10:21:44.822Z",
        "created_by_id" => 1,
        "invite_email" => nil,
        "invite_token" => nil,
        "invite_accepted_at" => nil,
        "user" => {
          "id" => 99,
          "public_email" => original_member.email,
          "username" => 'test'
        },
        "user_id" => 19
      }]
    end

    let(:members_mapper) do
      described_class.new(
        exported_members: exported_members, user: user, importable: importable
      )
    end

    context 'when importable is Project with restricted membership' do
      let_it_be(:group) { create(:group, membership_lock: true) }
      let_it_be(:importable) { create(:project, :public, group: group) }

      it 'does not create any members' do
        expect { members_mapper }.not_to change { importable.reload.members.count }
      end
    end
  end

  context 'when the importer is a non-admin top-level group Owner' do
    let_it_be(:root_group) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: root_group) }
    let_it_be(:owner) { create(:user, owner_of: root_group) }
    let_it_be(:enterprise_user) { create(:enterprise_user, enterprise_group: root_group) }
    let_it_be(:other_enterprise_user) { create(:enterprise_user) }
    let_it_be(:regular_user) { create(:user) }

    let(:importer) { owner }
    let(:importable) { subgroup }
    let(:default_member) { false }
    let(:exported_members) { [exported_member(enterprise_user.email, 91)] }
    let(:logger) { instance_double(::Import::Framework::Logger, info: nil) }
    let(:mapping_message) { '[Project/Group Import] Mapped exported member to enterprise user' }
    let(:summary_message) { '[Project/Group Import] Enterprise user mapping summary' }
    let(:mapping_log) { hash_including(Labkit::Fields::LOG_MESSAGE => mapping_message) }
    let(:summary_log) { hash_including(Labkit::Fields::LOG_MESSAGE => summary_message) }

    let(:mapper) do
      described_class.new(exported_members: exported_members, user: importer, importable: importable,
        default_member: default_member)
    end

    def exported_member(email, old_id, **attrs)
      { 'access_level' => 30, 'notification_level' => 3, 'created_at' => '2024-01-01T00:00:00Z',
        'updated_at' => '2024-01-01T00:00:00Z', 'created_by_id' => nil,
        'user' => { 'id' => old_id, 'public_email' => email, 'username' => "user#{old_id}" } }.merge(attrs)
    end

    before do
      stub_licensed_features(domain_verification: true)
      allow(::Import::Framework::Logger).to receive(:build).and_return(logger)
    end

    context 'when on SaaS', :saas do
      it 'maps the enterprise user and adds them to the group' do
        expect(mapper.map[91]).to eq(enterprise_user.id)
        expect(subgroup.members.find_by(user: enterprise_user).access_level).to eq(Gitlab::Access::DEVELOPER)
      end

      context 'when the importable is a project' do
        let_it_be(:importable) { create(:project, group: subgroup) }
        let(:exported_members) { [exported_member(enterprise_user.email, 91, 'access_level' => 50)] }

        it 'maps the enterprise user and caps the access level at Maintainer' do
          expect(mapper.map[91]).to eq(enterprise_user.id)
          expect(importable.members.find_by(user: enterprise_user).access_level).to eq(Gitlab::Access::MAINTAINER)
        end
      end

      context 'when exported members are not enterprise users of the root group' do
        let(:exported_members) do
          [exported_member(regular_user.email, 92), exported_member(other_enterprise_user.email, 93)]
        end

        it 'maps them to the importer without creating members' do
          expect(mapper.map[92]).to eq(owner.id)
          expect(mapper.map[93]).to eq(owner.id)
          expect(importable.members.where(user: [regular_user, other_enterprise_user])).to be_empty
        end
      end

      context 'when an exported member is an invite' do
        let(:exported_members) do
          [exported_member(enterprise_user.email, 91),
            { 'access_level' => 20, 'invite_email' => 'outside@example.com', 'invite_token' => 'tok' }]
        end

        it 'does not create the invite' do
          mapper.map

          expect(Member.find_by(invite_email: 'outside@example.com')).to be_nil
        end
      end

      context 'when no exported member has an email' do
        let(:exported_members) { [{ 'access_level' => 20, 'invite_email' => 'outside@example.com' }] }

        it 'maps nothing and logs the summary' do
          expect(mapper.map).to be_empty
          expect(logger).not_to have_received(:info).with(mapping_log)
          expect(logger).to have_received(:info).with(hash_including(
            Labkit::Fields::LOG_MESSAGE => summary_message, exported_members_count: 1, mapped_members_count: 0
          )).once
        end
      end

      context 'when the enterprise user is deactivated' do
        let_it_be(:deactivated_user) { create(:enterprise_user, :deactivated, enterprise_group: root_group) }
        let(:exported_members) { [exported_member(deactivated_user.email, 94)] }

        it 'maps the user and adds them to the group' do
          expect(mapper.map[94]).to eq(deactivated_user.id)
          expect(subgroup.members.find_by(user: deactivated_user).access_level).to eq(Gitlab::Access::DEVELOPER)
        end
      end

      context 'when the enterprise user is not an active or deactivated human' do
        where(:trait) { [:blocked, :banned, :blocked_pending_approval, :service_account] }

        with_them do
          let(:inactive_user) { create(:enterprise_user, trait, enterprise_group: root_group) }
          let(:exported_members) { [exported_member(inactive_user.email, 94)] }

          it 'maps them to the importer without creating a member' do
            expect(mapper.map[94]).to eq(owner.id)
            expect(Member.where(user: inactive_user, source: importable)).to be_empty
          end
        end
      end

      context 'when the exported email differs only in case' do
        let(:exported_members) { [exported_member(enterprise_user.email.upcase, 91)] }

        it 'maps the enterprise user' do
          expect(mapper.map[91]).to eq(enterprise_user.id)
        end
      end

      context 'when the exported emails span more than one batch' do
        let_it_be(:second_enterprise_user) { create(:enterprise_user, enterprise_group: root_group) }
        let(:exported_members) do
          [exported_member(enterprise_user.email, 91), exported_member(second_enterprise_user.email, 95)]
        end

        before do
          stub_const("#{EE::Gitlab::ImportExport::MembersMapper}::EMAIL_BATCH_SIZE", 1)
        end

        it 'maps the enterprise users from every batch' do
          expect(mapper.map).to include(91 => enterprise_user.id, 95 => second_enterprise_user.id)
        end

        it 'does not look up the mapped emails again in one unbatched query' do
          recorder = ActiveRecord::QueryRecorder.new { mapper.map }
          email_queries = recorder.log.grep(/FROM "users".*LOWER\("users"\."email"\)/i)

          expect(email_queries.map { |sql| sql.scan(/LOWER\('[^']+'\)/i).size }).to eq([1, 1])
        end
      end

      context 'when the exported member has tampered attributes' do
        let(:exported_members) do
          [exported_member(enterprise_user.email, 91, 'requested_at' => Time.current, 'invite_token' => 'x',
            'state' => 1)]
        end

        it 'drops them and maps the enterprise user' do
          expect(mapper.map[91]).to eq(enterprise_user.id)

          member = GroupMember.find_by(source_id: subgroup.id, user_id: enterprise_user.id)

          expect(member).to have_attributes(requested_at: nil, invite_token: nil, state: Member::STATE_ACTIVE)
        end
      end

      context 'when the enterprise user is already a member of the importable' do
        let(:exported_members) { [exported_member(enterprise_user.email, 91, 'access_level' => Gitlab::Access::GUEST)] }

        before_all do
          subgroup.add_maintainer(enterprise_user)
        end

        it 'maps the enterprise user and keeps the existing membership' do
          expect(mapper.map[91]).to eq(enterprise_user.id)
          expect(subgroup.members.where(user: enterprise_user).pluck(:access_level)).to eq([Gitlab::Access::MAINTAINER])
        end
      end

      context 'when exported members have a created_by_id' do
        let_it_be(:second_enterprise_user) { create(:enterprise_user, enterprise_group: root_group) }
        let(:exported_members) do
          [exported_member(enterprise_user.email, 91, 'created_by_id' => 95),
            exported_member(second_enterprise_user.email, 95, 'created_by_id' => 92),
            exported_member(regular_user.email, 92)]
        end

        it 'keeps the creator only when it is a mapped enterprise user' do
          mapper.map

          expect(subgroup.members.find_by(user: enterprise_user).created_by_id).to eq(second_enterprise_user.id)
          expect(subgroup.members.find_by(user: second_enterprise_user).created_by_id).to be_nil
        end
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(file_import_enterprise_user_mapping: false)
        end

        it 'maps nothing and writes no enterprise log' do
          expect(mapper.map[91]).to eq(owner.id)
          expect(subgroup.members).to be_empty
          expect(logger).not_to have_received(:info).with(mapping_log)
          expect(logger).not_to have_received(:info).with(summary_log)
        end
      end

      context 'when domain_verification is not licensed' do
        before do
          stub_licensed_features(domain_verification: false)
        end

        it 'maps nothing' do
          expect(mapper.map[91]).to eq(owner.id)
        end
      end

      context 'when the importer is a Maintainer of the root group' do
        let(:importer) { create(:user, maintainer_of: root_group) }

        it 'maps nothing' do
          expect(mapper.map[91]).to eq(importer.id)
        end
      end

      context 'when the importer is an Owner of the subgroup only' do
        let(:importer) { create(:user, owner_of: subgroup) }

        it 'maps nothing' do
          expect(mapper.map[91]).to eq(importer.id)
        end
      end

      context 'when the importer is an Owner of the root group through a group share' do
        let(:importer) { create(:user) }

        before do
          create(:group_group_link, :owner, shared_group: root_group,
            shared_with_group: create(:group, owners: importer))
        end

        it 'maps nothing' do
          expect(root_group.has_owner?(importer)).to be(true)
          expect(mapper.map[91]).to eq(importer.id)
        end
      end

      context 'when the importer is a service account Owner of the root group' do
        let(:importer) { create(:service_account, owner_of: root_group) }

        it 'maps the enterprise user' do
          expect(mapper.map[91]).to eq(enterprise_user.id)
        end
      end

      context 'when the importable is a project in a personal namespace' do
        let_it_be(:personal_owner) { create(:user, :with_namespace) }
        let(:importer) { personal_owner }
        let_it_be(:importable) { create(:project, namespace: personal_owner.namespace) }

        it 'maps nothing' do
          expect(mapper.map[91]).to eq(personal_owner.id)
        end
      end

      context 'when the importable is a new top-level group' do
        let(:importable) { create(:group, owners: owner) }

        it 'maps nothing' do
          expect(mapper.map[91]).to eq(owner.id)
        end
      end

      context 'when the importable is a project with restricted membership' do
        let_it_be(:importable) { create(:project, group: create(:group, parent: root_group, membership_lock: true)) }

        it 'maps the enterprise user without creating members and logs the membership locked path' do
          expect(mapper.map[91]).to eq(enterprise_user.id)
          expect(importable.members).to be_empty
          expect(logger).to have_received(:info).with(hash_including(
            Labkit::Fields::LOG_MESSAGE => summary_message,
            mapping_path: described_class::MAPPING_PATH_MEMBERSHIP_LOCKED,
            mapped_without_membership_count: 1
          )).once
        end
      end

      context 'when default_member is true' do
        let(:default_member) { true }

        it 'adds the importer and maps the enterprise user' do
          expect(mapper.map[91]).to eq(enterprise_user.id)
          expect(subgroup.members.exists?(user: owner)).to be(true)
        end
      end

      context 'when the importer is an admin' do
        let(:importer) { create(:admin) }
        let(:exported_members) { [exported_member(regular_user.email, 92)] }

        where(:flag_enabled) { [true, false] }

        with_them do
          before do
            stub_feature_flags(file_import_enterprise_user_mapping: flag_enabled)
          end

          it 'maps every matching user' do
            expect(mapper.map[92]).to eq(regular_user.id)
          end
        end
      end

      describe 'logging' do
        let(:exported_members) { [exported_member(enterprise_user.email, 91), exported_member(regular_user.email, 92)] }

        it 'logs each mapped member once' do
          mapper.map

          expect(logger).to have_received(:info).with(hash_including(
            Labkit::Fields::LOG_MESSAGE => mapping_message,
            Labkit::Fields::GL_USER_ID => enterprise_user.id,
            Labkit::Fields::GL_ROOT_NAMESPACE_ID => root_group.id,
            Labkit::Fields::GL_NAMESPACE_ID => subgroup.id,
            importing_user_id: owner.id,
            exported_user_id: 91,
            importable_type: 'Group'
          )).once
          expect(logger).to have_received(:info).with(mapping_log).once
        end

        context 'when the exported user id is not numeric' do
          let(:exported_members) { [exported_member(enterprise_user.email, 'not-an-id')] }

          it 'logs a nil exported user id' do
            mapper.map

            expect(logger).to have_received(:info).with(hash_including(
              Labkit::Fields::LOG_MESSAGE => mapping_message, exported_user_id: nil
            )).once
          end
        end

        context 'when the exported user id is a numeric string' do
          let(:exported_members) { [exported_member(enterprise_user.email, '91')] }

          it 'logs the exported user id as an integer' do
            mapper.map

            expect(logger).to have_received(:info).with(hash_including(
              Labkit::Fields::LOG_MESSAGE => mapping_message, exported_user_id: 91
            )).once
          end
        end

        it 'logs the owner path summary' do
          mapper.map

          expect(logger).to have_received(:info).with(hash_including(
            Labkit::Fields::LOG_MESSAGE => summary_message,
            Labkit::Fields::GL_USER_ID => owner.id,
            mapping_path: described_class::MAPPING_PATH_ENTERPRISE_OWNER,
            exported_members_count: 2,
            mapped_members_count: 1,
            skipped_members_count: 1
          )).once
        end

        context 'when the importable is a project' do
          let_it_be(:importable) { create(:project, group: subgroup) }

          it 'logs the project id' do
            mapper.map

            expect(logger).to have_received(:info).with(hash_including(
              Labkit::Fields::LOG_MESSAGE => mapping_message,
              Labkit::Fields::GL_PROJECT_ID => importable.id,
              importable_type: 'Project'
            )).once
          end
        end

        context 'when the importer is a root Maintainer' do
          let(:importer) { create(:user, maintainer_of: root_group) }

          it 'logs a summary without a mapping path' do
            mapper.map

            expect(logger).not_to have_received(:info).with(mapping_log)
            expect(logger).to have_received(:info).with(hash_including(
              Labkit::Fields::LOG_MESSAGE => summary_message,
              Labkit::Fields::GL_USER_ID => importer.id,
              mapping_path: described_class::MAPPING_PATH_NONE,
              exported_members_count: 2,
              mapped_members_count: 0,
              skipped_members_count: 2
            )).once
          end
        end
      end

      context 'when the root group blocks seat overages' do
        let(:seats) { 1 }
        let(:exported_members) { [exported_member(enterprise_user.email, 91)] }
        # A fresh record, so the root group's subscription and settings are not the frozen let_it_be ones.
        let(:importable) { Group.find(subgroup.id) }

        before do
          create(:gitlab_subscription, :ultimate, namespace: root_group, seats: seats)
          NamespaceSetting.find(root_group.id).update!(seat_control: :block_overages)
        end

        context 'when the new billable members do not fit in the seats' do
          it 'maps the enterprise user without a membership and logs the seat limit path' do
            expect(mapper.map[91]).to eq(enterprise_user.id)
            expect(subgroup.members).to be_empty
            expect(logger).to have_received(:info).with(hash_including(
              Labkit::Fields::LOG_MESSAGE => summary_message,
              mapping_path: described_class::MAPPING_PATH_SEAT_LIMIT_EXCEEDED,
              mapped_members_count: 1,
              mapped_without_membership_count: 1
            )).once
          end
        end

        context 'when only some of the new billable members fit in the seats' do
          let(:seats) { 2 }
          let(:second_enterprise_user) { create(:enterprise_user, enterprise_group: root_group) }
          let(:exported_members) do
            [exported_member(enterprise_user.email, 91), exported_member(second_enterprise_user.email, 95)]
          end

          it 'maps both enterprise users without creating any membership' do
            expect(mapper.map).to include(91 => enterprise_user.id, 95 => second_enterprise_user.id)
            expect(subgroup.members).to be_empty
            expect(logger).to have_received(:info).with(hash_including(
              mapping_path: described_class::MAPPING_PATH_SEAT_LIMIT_EXCEEDED,
              mapped_members_count: 2,
              mapped_without_membership_count: 2
            )).once
          end
        end

        context 'when the members beyond the free seats have non-billable roles' do
          let(:seats) { 2 }
          let(:guest_user) { create(:enterprise_user, enterprise_group: root_group) }
          let(:exported_members) do
            [exported_member(enterprise_user.email, 91), exported_member(guest_user.email, 95, 'access_level' => 10)]
          end

          it 'maps the enterprise users and adds them to the group' do
            expect(mapper.map).to include(91 => enterprise_user.id, 95 => guest_user.id)
            expect(subgroup.members.find_by(user: guest_user).access_level).to eq(Gitlab::Access::GUEST)
            expect(subgroup.members.exists?(user: enterprise_user)).to be(true)
          end
        end

        context 'when the enterprise user is already billable in the root group' do
          let(:seats) { 2 }

          before_all do
            root_group.add_developer(enterprise_user)
          end

          it 'maps the enterprise user and adds them to the group' do
            expect(mapper.map[91]).to eq(enterprise_user.id)
            expect(subgroup.members.exists?(user: enterprise_user)).to be(true)
            expect(logger).to have_received(:info).with(hash_including(
              mapping_path: described_class::MAPPING_PATH_ENTERPRISE_OWNER, mapped_without_membership_count: 0
            )).once
          end
        end

        context 'when every new member is deactivated' do
          let(:deactivated_user) { create(:enterprise_user, :deactivated, enterprise_group: root_group) }
          let(:exported_members) { [exported_member(deactivated_user.email, 94)] }

          it 'adds the member even though no seat is free' do
            expect(mapper.map[94]).to eq(deactivated_user.id)
            expect(subgroup.members.exists?(user: deactivated_user)).to be(true)
          end
        end

        context 'when the importable is a project and one new member is deactivated' do
          let(:seats) { 2 }
          let(:importable) { Project.find(create(:project, group: subgroup).id) }
          let(:deactivated_user) { create(:enterprise_user, :deactivated, enterprise_group: root_group) }
          let(:exported_members) do
            [exported_member(enterprise_user.email, 91), exported_member(deactivated_user.email, 94)]
          end

          it 'does not count the deactivated user against the seats and adds both members' do
            expect(mapper.map).to include(91 => enterprise_user.id, 94 => deactivated_user.id)
            expect(importable.members.where(user: [enterprise_user, deactivated_user]).count).to eq(2)
            expect(logger).to have_received(:info).with(hash_including(
              mapping_path: described_class::MAPPING_PATH_ENTERPRISE_OWNER, mapped_without_membership_count: 0
            )).once
          end
        end
      end

      context 'when the root group does not block seat overages' do
        let(:importable) { Group.find(subgroup.id) }

        before do
          create(:gitlab_subscription, :ultimate, namespace: root_group, seats: 1)
        end

        it 'maps the enterprise user and adds them to the group' do
          expect(mapper.map[91]).to eq(enterprise_user.id)
          expect(subgroup.members.exists?(user: enterprise_user)).to be(true)
        end
      end
    end

    context 'when not on SaaS' do
      it 'maps nothing' do
        expect(mapper.map[91]).to eq(owner.id)
      end
    end
  end
end
