# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuthorizedProjectUpdate::ProjectRecalculatePerUserService, '#execute', feature_category: :groups_and_projects do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user) }
  let_it_be(:another_user) { create(:user) }

  subject(:execute) { described_class.new(project, user).execute }

  shared_examples 'recalculating the user on the project' do
    it 'returns success' do
      expect(execute.success?).to be(true)
    end

    context 'when there are no changes to be made' do
      it 'does not change authorizations' do
        expect { execute }.not_to(change { ProjectAuthorization.count })
      end
    end

    context 'when there are changes to be made' do
      context 'when addition is required' do
        before do
          project.add_developer(user)
          project.add_developer(another_user)
          project.project_authorizations.where(user: [user, another_user]).delete_all
        end

        it 'adds a new authorization record for the specific user' do
          expect { execute }.to(
            change { project.project_authorizations.where(user: user).count }
            .from(0).to(1)
          )
        end

        it 'does not add a new authorization record for the other user' do
          expect { execute }.not_to(
            change { project.project_authorizations.where(user: another_user).count }
          )
        end

        it 'adds a new authorization record with the correct access level for the specific user' do
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
          create(:project_authorization, user: another_user, project: project)
        end

        it 'removes the authorization record for the specific user' do
          expect { execute }.to(
            change { project.project_authorizations.where(user: user).count }
            .from(1).to(0)
          )
        end

        it 'does not remove the authorization record for the other user' do
          expect { execute }.not_to(
            change { project.project_authorizations.where(user: another_user).count }
          )
        end
      end

      context 'when an update in access level is required' do
        before do
          project.add_developer(user)
          project.add_developer(another_user)
          project.project_authorizations.where(user: [user, another_user]).delete_all
          create(:project_authorization, project: project, user: user, access_level: Gitlab::Access::GUEST)
          create(:project_authorization, project: project, user: another_user, access_level: Gitlab::Access::GUEST)
        end

        it 'updates the authorization of the specific user to the correct access level' do
          expect { execute }.to(
            change { project.project_authorizations.find_by(user: user).access_level }
              .from(Gitlab::Access::GUEST).to(Gitlab::Access::DEVELOPER)
          )
        end

        it 'does not update the authorization of the other user to the correct access level' do
          expect { execute }.not_to(
            change { project.project_authorizations.find_by(user: another_user).access_level }
              .from(Gitlab::Access::GUEST)
          )
        end
      end
    end

    context 'when the user is blocked' do
      let_it_be(:user) { create(:user, :blocked) }

      before do
        project.add_developer(user)
        project.project_authorizations.where(user: user).delete_all
      end

      it 'does not add the missing authorization' do
        expect { execute }.not_to(change { project.project_authorizations.where(user: user).count })
      end
    end
  end

  context 'with the shared write path' do
    it "writes this project under the user's lock, with no comparison before it" do
      expect(Authz::ProjectAuthorizations::RecalculateUserService).not_to receive(:new)
      expect(Projects::Members::EffectiveAccessLevelPerUserFinder).not_to receive(:new)
      expect_next_instance_of(Authz::ProjectAuthorizations::WriteBatchService, user_id: user.id) do |service|
        expect(service).to receive(:execute).with([project.id]).and_call_original
      end

      execute
    end

    it 'logs the rows it wrote' do
      project.add_developer(user)
      project.project_authorizations.where(user: user).delete_all
      allow(Gitlab::AppJsonLogger).to receive(:info).and_call_original

      execute

      expect(Gitlab::AppJsonLogger).to have_received(:info).with(
        event: 'project_authorizations_project_refresh',
        Labkit::Fields::GL_PROJECT_ID.to_sym => project.id,
        Labkit::Fields::GL_USER_ID.to_sym => user.id,
        'project_refresh.service': described_class.name,
        'project_refresh.rows_added_count': 1,
        'project_refresh.rows_deleted_count': 0,
        'project_refresh.shared_write_path': true
      )
    end

    it_behaves_like 'recalculating the user on the project'
  end

  context 'when authz_project_refresh_write_path is disabled' do
    before do
      stub_feature_flags(authz_project_refresh_write_path: false)
    end

    it 'still uses the shared write path, which per-user refreshes take from authz_refresh_write_path' do
      expect(Authz::ProjectAuthorizations::WriteBatchService).to receive(:new).with(user_id: user.id).and_call_original

      execute
    end
  end

  context 'when authz_refresh_write_path is on for another user only' do
    before do
      stub_feature_flags(authz_refresh_write_path: another_user)
    end

    it 'keeps the old path for this user' do
      expect(Authz::ProjectAuthorizations::WriteBatchService).not_to receive(:new)

      execute
    end
  end

  context 'when called inside a transaction' do
    it 'keeps the old path, which the shared path refuses to run in' do
      expect(Authz::ProjectAuthorizations::WriteBatchService).not_to receive(:new)

      ProjectAuthorization.transaction { execute }
    end
  end

  context 'when authz_refresh_write_path is disabled' do
    before do
      stub_feature_flags(authz_refresh_write_path: false)
    end

    it_behaves_like 'recalculating the user on the project'
  end
end
