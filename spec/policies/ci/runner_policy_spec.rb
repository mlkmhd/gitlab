# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::RunnerPolicy, feature_category: :runner_core do
  let_it_be(:owner) { create(:user) }

  subject(:policy) { described_class.new(user, runner) }

  include_context 'with runner policy environment'

  describe 'ability :read_runner' do
    it_behaves_like 'runner policy not allowed for levels lower than maintainer', :read_runner
    it_behaves_like 'runner policy', :read_runner
  end

  describe 'ability :read_runner_job' do
    it_behaves_like 'runner policy not allowed for levels lower than maintainer', :read_runner_job

    context 'without access' do
      let_it_be(:user) { create(:user) }

      it_behaves_like 'does not allow accessing runners/runner managers on any scope', :read_runner_job
    end

    context 'with guest access' do
      let(:user) { guest }

      it_behaves_like 'does not allow accessing runners/runner managers on any scope', :read_runner_job
    end

    context 'with reporter access' do
      let(:user) { reporter }

      it_behaves_like 'does not allow accessing runners/runner managers on any scope', :read_runner_job
    end

    context 'with developer access' do
      let(:user) { developer }

      it_behaves_like 'does not allow accessing runners/runner managers on any scope', :read_runner_job
    end

    context 'with maintainer access' do
      let(:user) { maintainer }

      context 'with instance runner' do
        let(:runner) { instance_runner }

        it { expect_disallowed :read_runner_job }
      end

      context 'with group runner' do
        let(:runner) { group_runner }

        it { expect_allowed :read_runner_job }
      end

      it_behaves_like 'runner policy with project runner', :read_runner_job
    end

    it_behaves_like 'runner policy for user with owner access', :read_runner_job
    it_behaves_like 'runner policy for admin user', :read_runner_job
  end

  describe 'ability :read_runner_sensitive_data' do
    it_behaves_like 'runner policy not allowed for levels lower than maintainer', :read_runner_sensitive_data
    it_behaves_like 'runner policy', :read_runner_sensitive_data, scope: %i[group_runner project_runner]

    context 'with instance runner' do
      let(:runner) { instance_runner }

      context 'with owner access' do
        let(:user) { owner }

        # Non-admin users don't have access to instance runner sensitive data
        it { expect_disallowed :read_runner_sensitive_data }
      end

      context 'with admin access' do
        let_it_be(:user) { create(:admin) }

        # Admin users don't have access to instance runner sensitive data, unless admin mode is enabled
        it { expect_disallowed :read_runner_sensitive_data }

        context 'when admin mode is enabled', :enable_admin_mode do
          it { expect_allowed :read_runner_sensitive_data }
        end
      end
    end
  end

  describe 'ability :update_runner' do
    it_behaves_like 'runner policy not allowed for levels lower than maintainer', :update_runner

    context 'with maintainer access' do
      let(:user) { maintainer }

      context 'with a project runner associated with one project' do
        let(:runner) { create(:ci_runner, :project, projects: [owner_project]) }

        it { expect_allowed :update_runner }

        context 'when user is only a developer in the owning project' do
          let_it_be(:user, freeze: false) { create(:user, developer_of: owner_project) }

          it { expect_disallowed :update_runner }
        end
      end

      context 'with instance runner' do
        let(:runner) { instance_runner }

        it { expect_disallowed :update_runner }
      end

      context 'with group runner' do
        let(:runner) { group_runner }

        it { expect_disallowed :update_runner }
      end

      it_behaves_like 'runner policy with project runner', :update_runner
    end

    it_behaves_like 'runner policy for user with owner access', :update_runner
  end

  describe 'ability :reset_runner_authentication_token' do
    it_behaves_like 'runner policy not allowed for levels lower than maintainer', :reset_runner_authentication_token

    context 'with maintainer access' do
      let(:user) { maintainer }

      context 'with a project runner associated with one project' do
        let(:runner) { create(:ci_runner, :project, projects: [owner_project]) }

        it { expect_allowed :reset_runner_authentication_token }

        context 'when user is only a developer in the owning project' do
          let_it_be(:user, freeze: false) { create(:user, developer_of: owner_project) }

          it { expect_disallowed :reset_runner_authentication_token }
        end
      end

      context 'with instance runner' do
        let(:runner) { instance_runner }

        it { expect_disallowed :reset_runner_authentication_token }
      end

      context 'with group runner' do
        let(:runner) { group_runner }

        it { expect_disallowed :reset_runner_authentication_token }
      end

      it_behaves_like 'runner policy with project runner', :reset_runner_authentication_token
    end

    it_behaves_like 'runner policy for user with owner access', :reset_runner_authentication_token
  end

  describe 'ability :read_ephemeral_token' do
    let_it_be(:runner) { create(:ci_runner, creator: owner) }

    let(:creator) { owner }

    context 'with request made by creator' do
      let(:user) { creator }

      it { expect_allowed :read_ephemeral_token }
    end

    context 'with request made by another user' do
      let(:user) { create(:admin) }

      it { expect_disallowed :read_ephemeral_token }
    end
  end

  context 'when the owner project is archived' do
    let_it_be(:archived_project) { create(:project, :archived, owners: owner) }
    let_it_be(:runner) { create(:ci_runner, :project, projects: [archived_project]) }

    let(:user) { owner }

    it 'allows reading and deleting the runner but not changing it' do
      expect_allowed(:read_runner, :delete_runner)
      expect_disallowed(:update_runner, :assign_runner)
    end

    context 'when the runner is also assigned to another project' do
      let_it_be(:second_project) { create(:project, owners: owner) }
      let_it_be(:runner) { create(:ci_runner, :project, projects: [archived_project, second_project]) }

      it { expect_disallowed(:update_runner, :assign_runner) }
    end

    context 'with an admin user' do
      let(:user) { create(:admin) }

      it { expect_disallowed(:update_runner, :assign_runner, :delete_runner) }

      context 'when admin mode is enabled', :enable_admin_mode do
        it 'allows deleting the runner but not changing it' do
          expect_allowed(:delete_runner)
          expect_disallowed(:update_runner, :assign_runner)
        end
      end
    end
  end

  context 'when the owner group is archived' do
    let_it_be(:archived_group) { create(:group, :archived, owners: owner) }
    let_it_be(:runner) { create(:ci_runner, :group, groups: [archived_group]) }

    let(:user) { owner }

    it 'allows reading and deleting the runner but not changing it' do
      expect_allowed(:read_runner, :delete_runner)
      expect_disallowed(:update_runner)
    end
  end
end
