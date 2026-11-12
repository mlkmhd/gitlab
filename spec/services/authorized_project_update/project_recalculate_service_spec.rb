# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuthorizedProjectUpdate::ProjectRecalculateService, '#execute', feature_category: :groups_and_projects do
  let_it_be(:project) { create(:project) }

  subject(:execute) { described_class.new(project).execute }

  shared_examples 'recalculating the project' do
    it 'returns success' do
      expect(execute.success?).to be(true)
    end

    context 'when there are no changes to be made' do
      it 'does not change authorizations' do
        expect { execute }.not_to(change { ProjectAuthorization.count })
      end
    end

    context 'when there are changes to be made' do
      let_it_be(:user) { create(:user) }

      context 'when addition is required' do
        before do
          project.add_developer(user)
          project.project_authorizations.where(user: user).delete_all
        end

        it 'adds a new authorization record' do
          expect { execute }.to(
            change { project.project_authorizations.where(user: user).count }
            .from(0).to(1)
          )
        end

        it 'adds a new authorization record with the correct access level' do
          execute

          project_authorization = project.project_authorizations.where(
            user: user,
            access_level: Gitlab::Access::DEVELOPER
          )

          expect(project_authorization).to exist
        end
      end

      context 'when removal is required' do
        before do
          create(:project_authorization, user: user, project: project)
        end

        it 'removes the authorization record' do
          expect { execute }.to(
            change { project.project_authorizations.where(user: user).count }
            .from(1).to(0)
          )
        end
      end

      context 'when an update in access level is required' do
        before do
          project.add_developer(user)
          project.project_authorizations.where(user: user).delete_all
          create(:project_authorization, project: project, user: user, access_level: Gitlab::Access::GUEST)
        end

        it 'updates the authorization of the user to the correct access level' do
          expect { execute }.to(
            change { project.project_authorizations.find_by(user: user).access_level }
              .from(Gitlab::Access::GUEST).to(Gitlab::Access::DEVELOPER)
          )
        end
      end
    end

    context 'when there are changes for a blocked user' do
      let_it_be(:active_user) { create(:user) }
      let_it_be(:blocked_member) { create(:user, :blocked) }
      let_it_be(:blocked_non_member) { create(:user, :blocked) }

      before do
        project.add_developer(active_user)
        project.add_developer(blocked_member)
        project.project_authorizations.where(user: [active_user, blocked_member]).delete_all
        create(:project_authorization, project: project, user: blocked_non_member)
      end

      it 'leaves the authorizations of the blocked users as they are' do
        expect { execute }.not_to(
          change { project.project_authorizations.where(user: [blocked_member, blocked_non_member]).pluck(:user_id) }
        )
      end

      it 'still refreshes the active user' do
        expect { execute }.to(
          change { project.project_authorizations.where(user: active_user).count }.from(0).to(1)
        )
      end

      it 'looks up only the users whose authorizations would change' do
        expect(Authz::ProjectAuthorizations::BlockedUserRefreshSkip).to receive(:skipped_user_ids).with(
          contain_exactly(active_user.id, blocked_member.id, blocked_non_member.id), skipped_in: :project_recalculate
        ).and_call_original

        execute
      end

      context 'when skip_authorization_refresh_for_blocked_users is disabled' do
        before do
          stub_feature_flags(skip_authorization_refresh_for_blocked_users: false)
        end

        it 'refreshes the blocked users too' do
          execute

          expect(project.project_authorizations.where(user: [blocked_member, blocked_non_member]).pluck(:user_id))
            .to contain_exactly(blocked_member.id)
        end
      end
    end
  end

  shared_examples 'logging the refresh' do |shared_write_path:|
    let_it_be(:user) { create(:user) }

    before do
      allow(Gitlab::AppJsonLogger).to receive(:info).and_call_original
    end

    it 'logs the rows it was asked to change next to the rows it wrote' do
      project.add_developer(user)
      project.project_authorizations.where(user: user).delete_all

      execute

      expect(Gitlab::AppJsonLogger).to have_received(:info).with(
        event: 'project_authorizations_project_refresh',
        Labkit::Fields::GL_PROJECT_ID.to_sym => project.id,
        Labkit::Fields::GL_USER_ID.to_sym => nil,
        'project_refresh.service': described_class.name,
        'project_refresh.requested_add_count': 1,
        'project_refresh.requested_remove_count': 0,
        'project_refresh.rows_added_count': 1,
        'project_refresh.rows_deleted_count': 0,
        'project_refresh.shared_write_path': shared_write_path
      )
    end

    it 'logs nothing when there is nothing to change' do
      execute

      expect(Gitlab::AppJsonLogger).not_to have_received(:info)
        .with(hash_including(event: 'project_authorizations_project_refresh'))
    end
  end

  context 'with the shared write path' do
    it 'recalculates through RecalculateProjectService' do
      expect(Authz::ProjectAuthorizations::RecalculateProjectService).to receive(:new)
        .with(project.id).and_call_original

      execute
    end

    it_behaves_like 'recalculating the project'
    it_behaves_like 'logging the refresh', shared_write_path: true
  end

  context 'when authz_project_refresh_write_path is on for another project only' do
    before do
      stub_feature_flags(authz_project_refresh_write_path: create(:project))
    end

    it 'keeps the old path for this project' do
      expect(Authz::ProjectAuthorizations::RecalculateProjectService).not_to receive(:new)

      execute
    end
  end

  context 'when called inside a transaction' do
    it 'keeps the old path, which the shared path refuses to run in' do
      expect(Authz::ProjectAuthorizations::RecalculateProjectService).not_to receive(:new)

      ProjectAuthorization.transaction { execute }
    end
  end

  context 'when authz_project_refresh_write_path is disabled' do
    before do
      stub_feature_flags(authz_project_refresh_write_path: false)
    end

    it 'reads the current authorizations from the primary' do
      session = ::Gitlab::Database::LoadBalancing::SessionMap.current(ProjectAuthorization.load_balancer)

      expect(session).to receive(:use_primary).and_call_original

      execute
    end

    it_behaves_like 'recalculating the project'
    it_behaves_like 'logging the refresh', shared_write_path: false
  end
end
