# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::AllBranchesRulePolicy, feature_category: :source_code_management do
  let_it_be(:user, freeze: false) { create(:user) }
  let_it_be(:group, freeze: false) { create(:group) }
  let_it_be(:project, freeze: false) { create(:project, group: group) }

  let(:branch_rule) { Projects::AllBranchesRule.new(project) }
  let(:custom_roles_enabled) { true }
  let(:approval_rules_enabled) { true }
  let(:external_status_checks_enabled) { true }

  subject(:policy) { described_class.new(user, branch_rule) }

  before do
    stub_licensed_features(
      custom_roles: custom_roles_enabled,
      multiple_approval_rules: approval_rules_enabled,
      external_status_checks: external_status_checks_enabled
    )
  end

  it { is_expected.to delegate_to(::ProjectPolicy) }

  shared_examples 'allows branch rule read and delete' do
    it { expect_disallowed(:create_branch_rule) }
    it { expect_allowed(:read_branch_rule) }
    it { expect_disallowed(:update_branch_rule) }
    it { expect_allowed(:delete_branch_rule) }

    it_behaves_like 'allows squash option crud'
  end

  shared_examples 'allows branch rule read only' do
    it { expect_disallowed(:create_branch_rule) }
    it { expect_allowed(:read_branch_rule) }
    it { expect_disallowed(:update_branch_rule) }
    it { expect_disallowed(:delete_branch_rule) }

    it_behaves_like 'allows squash option crud'
  end

  context 'as a maintainer' do
    before_all do
      project.add_maintainer(user)
    end

    it_behaves_like 'allows branch rule read and delete'

    context 'when approval rules are unlicensed' do
      let(:approval_rules_enabled) { false }

      it_behaves_like 'allows branch rule read and delete'
    end

    context 'when external status checks are unlicensed' do
      let(:external_status_checks_enabled) { false }

      it_behaves_like 'allows branch rule read and delete'
    end

    context 'when no deletable features are licensed' do
      let(:approval_rules_enabled) { false }
      let(:external_status_checks_enabled) { false }

      it_behaves_like 'allows branch rule read only'
    end
  end

  context 'as a developer' do
    let_it_be(:project_member, freeze: false) do
      create(:project_member, :developer, user: user, project: project)
    end

    it_behaves_like 'disallows branch rule crud'

    context 'with admin_protected_branch custom role' do
      let(:custom_roles_enabled) { true }

      before do
        create(:member_role, :admin_protected_branch, namespace: group, members: [project_member])
      end

      it_behaves_like 'disallows branch rule crud'
    end

    context 'with manage_merge_request_settings custom role' do
      before do
        create(:member_role, :manage_merge_request_settings, namespace: group, members: [project_member])
      end

      context 'when custom_roles feature is licensed' do
        let(:custom_roles_enabled) { true }

        it_behaves_like 'allows branch rule read and delete'

        context 'when approval rules are unlicensed' do
          let(:approval_rules_enabled) { false }

          it_behaves_like 'allows branch rule read and delete'
        end

        context 'when external status checks are unlicensed' do
          let(:external_status_checks_enabled) { false }

          it_behaves_like 'allows branch rule read and delete'
        end

        context 'when no deletable features are licensed' do
          let(:approval_rules_enabled) { false }
          let(:external_status_checks_enabled) { false }

          it_behaves_like 'allows branch rule read only'
        end
      end

      context 'when custom_roles feature is unlicensed' do
        let(:custom_roles_enabled) { false }

        it_behaves_like 'disallows branch rule crud'
      end
    end
  end
end
