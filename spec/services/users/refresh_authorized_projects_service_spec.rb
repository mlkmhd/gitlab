# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Users::RefreshAuthorizedProjectsService, feature_category: :user_management do
  # We're using let! here so that any expectations for the service class are not
  # triggered twice.
  # Older than the window in which safety-net refreshes skip new projects
  let!(:project) { create(:project, created_at: 1.day.ago) }

  let(:user) { project.namespace.first_owner }
  let(:service) { described_class.new(user) }

  # For deltas the finder would never compute on its own. These only arise when a
  # concurrent refresh has already applied the change, so they cannot be set up
  # through the database.
  def stub_refresh_delta(remove, add)
    allow_next_instance_of(AuthorizedProjectUpdate::FindRecordsDueForRefreshService) do |finder|
      allow(finder).to receive(:execute).and_return([remove, add])
    end
  end

  describe '#execute' do
    context 'callbacks' do
      let(:callback) { double('callback') }

      context 'incorrect_auth_found_callback callback' do
        let(:user) { create(:user) }
        let(:service) do
          described_class.new(user, incorrect_auth_found_callback: callback)
        end

        it 'is called' do
          access_level = Gitlab::Access::DEVELOPER
          create(:project_authorization, user: user, project: project, access_level: access_level)

          expect(callback).to receive(:call).with(project.id, access_level).once

          service.execute
        end
      end

      context 'missing_auth_found_callback callback' do
        let(:service) do
          described_class.new(user, missing_auth_found_callback: callback)
        end

        it 'is called' do
          ProjectAuthorization.delete_all

          expect(callback).to receive(:call).with(project.id, Gitlab::Access::OWNER).once

          service.execute
        end
      end
    end

    context 'when authorizations are outdated' do
      it 'removes authorizations that should be removed' do
        stale_project = create(:project)
        user.project_authorizations.create!(project: stale_project, access_level: Gitlab::Access::DEVELOPER)

        service.execute

        expect(user.project_authorizations.map(&:project_id)).to contain_exactly(project.id)
      end

      it 'inserts authorizations that should be added' do
        user.project_authorizations.delete_all

        service.execute

        authorizations = user.project_authorizations

        expect(authorizations.length).to eq(1)
        expect(authorizations[0].user_id).to eq(user.id)
        expect(authorizations[0].project_id).to eq(project.id)
        expect(authorizations[0].access_level).to eq(Gitlab::Access::OWNER)
      end

      it 'sets the access level to the highest of the paths granting access' do
        group = create(:group)
        group_project = create(:project, group: group)
        multi_path_user = create(:user)

        group.add_developer(multi_path_user)
        group_project.add_maintainer(multi_path_user)

        # Adding the members already refreshed the rows. Replace them with a row at the
        # lower of the two access levels, so the refresh has to correct an existing row
        # rather than only insert a missing one.
        multi_path_user.project_authorizations.delete_all
        multi_path_user.project_authorizations.create!(
          project: group_project, access_level: Gitlab::Access::DEVELOPER
        )

        expect { described_class.new(multi_path_user).execute }
          .to change { multi_path_user.project_authorizations.find_by(project_id: group_project.id).access_level }
          .from(Gitlab::Access::DEVELOPER).to(Gitlab::Access::MAINTAINER)
      end

      it 'updates project_authorizations_recalculated_at', :freeze_time do
        user.project_authorizations.delete_all

        default_date = Time.zone.local('2010')
        expect do
          service.execute
        end.to change { user.project_authorizations_recalculated_at }.from(default_date).to(Time.zone.now)
      end

      it 'returns a User' do
        user.project_authorizations.delete_all

        expect(service.execute).to be_an_instance_of(User)
      end

      it 'logs the details of the refresh' do
        source = :foo
        service = described_class.new(user, source: source)
        user.project_authorizations.delete_all

        expect(Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including(
            event: 'authorized_projects_refresh',
            user_id: user.id,
            'authorized_projects_refresh.source': source,
            'authorized_projects_refresh.rows_deleted_count': 0,
            'authorized_projects_refresh.rows_added_count': 1,
            'authorized_projects_refresh.rows_deleted_slice': [],
            'authorized_projects_refresh.rows_added_slice': [[user.id, project.id, Gitlab::Access::OWNER]]
          )
        )

        service.execute
      end

      it 'logs the rows actually affected rather than the ones requested' do
        existing = user.project_authorizations.find_by(project_id: project.id)

        # Nothing ends up being written: the removal names a project the user holds no row
        # for, and the addition duplicates a row that is already there.
        to_be_removed = [non_existing_record_id]
        to_be_added = [
          { user_id: user.id, project_id: project.id, access_level: existing.access_level }
        ]

        stub_refresh_delta(to_be_removed, to_be_added)

        expect(Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including(
            'authorized_projects_refresh.rows_deleted_count': 0,
            'authorized_projects_refresh.rows_added_count': 0,
            # The slices keep reporting what was requested, so the two can be compared.
            'authorized_projects_refresh.rows_deleted_slice': to_be_removed
          )
        )

        service.execute
      end

      it 'includes the related_class from the ambient context as the trigger' do
        user.project_authorizations.delete_all

        expect(Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including('authorized_projects_refresh.trigger': 'SomeCaller')
        )

        Gitlab::ApplicationContext.with_context(related_class: 'SomeCaller') do
          service.execute
        end
      end

      describe 'safety-net refresh metrics', :prometheus do
        let(:counter) { Gitlab::Metrics.counter(:gitlab_authorized_projects_safety_net_refresh_rows_total, 'test') }

        before do
          # A wrong access level makes the refresh both delete the stale row and insert a
          # corrected one, so each direction of the counter is exercised.
          user.project_authorizations.delete_all
          user.project_authorizations.create!(project: project, access_level: Gitlab::Access::DEVELOPER)

          allow(Gitlab::Metrics).to receive(:counter).and_call_original
          allow(Gitlab::Metrics).to receive(:counter)
            .with(:gitlab_authorized_projects_safety_net_refresh_rows_total, anything)
            .and_return(counter)
        end

        context 'when the refresh is marked with the safety-net purpose' do
          it 'increments the refresh trend counter for each direction, including the trigger label' do
            expect(counter).to receive(:increment)
              .with(hash_including(trigger: 'SomeCaller', direction: 'deleted'), 1)
            expect(counter).to receive(:increment)
              .with(hash_including(trigger: 'SomeCaller', direction: 'added'), 1)

            Gitlab::ApplicationContext.with_raw_context(
              authorized_projects_refresh_purpose: UserProjectAccessChangedService::SAFETY_NET_REFRESH_PURPOSE
            ) do
              Gitlab::ApplicationContext.with_context(related_class: 'SomeCaller') do
                service.execute
              end
            end
          end
        end

        context "when the refresh isn't marked with the safety-net purpose" do
          it 'does not increment the refresh trend counter' do
            expect(counter).not_to receive(:increment)

            service.execute
          end
        end

        # Guards the case that prompted this counting: a stale replica read still listed
        # rows for a project whose authorizations Postgres had already removed through the
        # `projects` cascade, so the refresh asked to delete rows that were already gone.
        context 'when the requested changes no longer match the rows in the database' do
          it 'does not increment the refresh trend counter' do
            stub_refresh_delta([non_existing_record_id], [])

            expect(counter).not_to receive(:increment)

            Gitlab::ApplicationContext.with_raw_context(
              authorized_projects_refresh_purpose: UserProjectAccessChangedService::SAFETY_NET_REFRESH_PURPOSE
            ) do
              service.execute
            end
          end
        end
      end
    end

    describe 'skipping projects pending their own refresh and deleted projects' do
      it 'skips them for safety-net refreshes' do
        expect(AuthorizedProjectUpdate::FindRecordsDueForRefreshService).to receive(:new)
          .with(user, hash_including(skip_projects_pending_refresh: true, skip_deleted_projects: true))
          .and_call_original

        Gitlab::ApplicationContext.with_raw_context(
          authorized_projects_refresh_purpose: UserProjectAccessChangedService::SAFETY_NET_REFRESH_PURPOSE
        ) do
          service.execute
        end
      end

      it 'does not skip them for other refreshes' do
        expect(AuthorizedProjectUpdate::FindRecordsDueForRefreshService).to receive(:new)
          .with(user, hash_including(skip_projects_pending_refresh: false, skip_deleted_projects: false))
          .and_call_original

        service.execute
      end
    end

    describe 'logging grants on archived projects' do
      let!(:archived_project) { create(:project, :archived, developers: user) }

      before do
        user.project_authorizations.where(project_id: archived_project.id).delete_all
      end

      it 'logs the grant and still writes it', :aggregate_failures do
        expect(Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including(
            'authorized_projects_refresh.rows_added_count': 1,
            'authorized_projects_refresh.archived_grants_count': 1
          )
        )

        service.execute

        expect(user.project_authorizations.exists?(project_id: archived_project.id)).to be(true)
      end

      context 'when log_archived_project_authorization_grants is disabled' do
        before do
          stub_feature_flags(log_archived_project_authorization_grants: false)
        end

        it 'does not look for them', :aggregate_failures do
          expect(AuthorizedProjectUpdate::FindRecordsDueForRefreshService).to receive(:new)
            .with(user, hash_including(archived_grants: nil)).and_call_original
          expect(Gitlab::AppJsonLogger).to receive(:info).with(
            hash_including('authorized_projects_refresh.archived_grants_count': nil)
          )

          service.execute
        end
      end
    end

    describe 'the shared write path' do
      before do
        user.project_authorizations.delete_all
      end

      it 'rechecks and writes only the changed projects' do
        stale_project = create(:project)
        user.project_authorizations.create!(project: stale_project, access_level: Gitlab::Access::DEVELOPER)

        expect(Authz::ProjectAuthorizations::RecalculateUserService).to receive(:new)
          .with(user.id, project_ids: contain_exactly(project.id, stale_project.id)).and_call_original

        service.execute

        expect(user.project_authorizations.pluck(:project_id, :access_level))
          .to contain_exactly([project.id, Gitlab::Access::OWNER])
      end

      it "waits for the user's writers before comparing" do
        calls = []
        allow(Authz::ProjectAuthorizations::WriteBatchService).to receive(:wait_for_writers)
          .and_wrap_original do |original, user_ids|
            calls << [:wait, user_ids]
            original.call(user_ids)
          end
        allow_next_instance_of(AuthorizedProjectUpdate::FindRecordsDueForRefreshService) do |finder|
          allow(finder).to receive(:execute).and_wrap_original do |original|
            calls << [:compare]
            original.call
          end
        end

        service.execute

        expect(calls.first(2)).to eq([[:wait, [user.id]], [:compare]])
      end

      it 'reads only the stored rows from the primary after waiting' do
        # Drop the stickiness from the setup's writes.
        ::Gitlab::Database::LoadBalancing::SessionMap.clear_session
        session = ::Gitlab::Database::LoadBalancing::SessionMap.current(ProjectAuthorization.load_balancer)
        on_primary = {}
        allow(ProjectAuthorization).to receive(:project_ids_and_access_levels_for).and_wrap_original do |original, id|
          on_primary[:stored] = session.use_primary?
          original.call(id)
        end
        allow_next_instance_of(Gitlab::ProjectAuthorizations) do |calculator|
          allow(calculator).to receive(:calculate).and_wrap_original do |original|
            on_primary[:calculation] = session.use_primary?
            original.call
          end
        end

        service.execute

        expect(on_primary).to eq(stored: true, calculation: false)
      end

      it 'logs the requested changes next to the rows written' do
        expect(Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including(
            'authorized_projects_refresh.shared_write_path': true,
            'authorized_projects_refresh.requested_remove_count': 0,
            'authorized_projects_refresh.requested_add_count': 1,
            'authorized_projects_refresh.rows_added_count': 1
          )
        )

        service.execute
      end

      context 'when the flag is disabled for the user' do
        before do
          stub_feature_flags(authz_refresh_write_path: create(:user))
        end

        it 'writes through ProjectAuthorizations::Changes as before' do
          expect(Authz::ProjectAuthorizations::RecalculateUserService).not_to receive(:new)
          expect(Authz::ProjectAuthorizations::WriteBatchService).not_to receive(:wait_for_writers)
          expect(Gitlab::AppJsonLogger).to receive(:info)
            .with(hash_including('authorized_projects_refresh.shared_write_path': false))

          service.execute

          expect(user.project_authorizations.pluck(:project_id)).to contain_exactly(project.id)
        end
      end
    end

    context 'when the refresh finds nothing to change' do
      it 'does not apply any authorization changes' do
        expect { service.execute }.not_to change { user.reload.project_authorizations_recalculated_at }
      end

      it 'does not log the refresh' do
        expect(Gitlab::AppJsonLogger).not_to receive(:info)
          .with(hash_including(event: 'authorized_projects_refresh'))

        service.execute
      end

      it 'returns a User' do
        expect(service.execute).to be_an_instance_of(User)
      end
    end

    context 'when the user is blocked' do
      let(:member_project) { create(:project) }
      let(:user) { create(:user, :blocked) }

      before do
        member_project.add_developer(user)
        user.project_authorizations.delete_all
        user.project_authorizations.create!(project: project, access_level: Gitlab::Access::DEVELOPER)
      end

      it 'neither removes stale authorizations nor adds missing ones' do
        expect { service.execute }.not_to change { user.project_authorizations.pluck(:project_id) }
      end

      it 'does not compute the authorizations' do
        expect(AuthorizedProjectUpdate::FindRecordsDueForRefreshService).not_to receive(:new)

        service.execute
      end

      it 'returns the user' do
        expect(service.execute).to eq(user)
      end

      context 'when skip_authorization_refresh_for_blocked_users is disabled' do
        before do
          stub_feature_flags(skip_authorization_refresh_for_blocked_users: false)
        end

        it 'refreshes the authorizations' do
          service.execute

          expect(user.project_authorizations.pluck(:project_id)).to contain_exactly(member_project.id)
        end
      end
    end
  end
end
