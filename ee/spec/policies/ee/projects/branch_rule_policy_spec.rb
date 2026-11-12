# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::BranchRulePolicy, feature_category: :source_code_management do
  let_it_be(:user, freeze: false) { create(:user) }
  let_it_be(:group, freeze: false) { create(:group) }
  let_it_be(:project, freeze: false) { create(:project, group: group) }
  let_it_be(:protected_branch, freeze: false) { create(:protected_branch, project: project) }

  let(:branch_rule) { Projects::BranchRule.new(project, protected_branch) }
  let(:unprotect_restrictions_enabled) { true }
  let(:custom_roles_enabled) { true }
  let(:approval_rules_enabled) { true }
  let(:external_status_checks_enabled) { true }
  let(:can_unprotect) { true }

  subject(:policy) { described_class.new(user, branch_rule) }

  before do
    stub_licensed_features(
      unprotection_restrictions: unprotect_restrictions_enabled,
      custom_roles: custom_roles_enabled
    )
    allow(protected_branch).to receive(:can_unprotect?).with(user).and_return(can_unprotect)
  end

  it { is_expected.to delegate_to(::ProjectPolicy) }

  shared_examples 'allows branch rule crud unless unprotect restrictions prevent' do |
    allowed: 'allows branch rule crud',
    restricted: 'disallows branch rule changes'
  |
    using RSpec::Parameterized::TableSyntax

    where(:unprotect_restrictions_enabled, :can_unprotect, :branch_rule_behavior) do
      true  | true  | allowed
      true  | false | restricted
      false | false | allowed
      false | true  | allowed
    end

    with_them do
      it_behaves_like params[:branch_rule_behavior]
    end
  end

  context 'as a maintainer' do
    before_all do
      project.add_maintainer(user)
    end

    it_behaves_like 'allows branch rule crud unless unprotect restrictions prevent'
  end

  context 'as a developer' do
    let_it_be(:project_member, freeze: false) do
      create(:project_member, :developer, user: user, project: project)
    end

    before_all do
      project.add_developer(user)
    end

    it_behaves_like 'disallows branch rule crud'

    context 'with admin_protected_branch custom role' do
      before do
        create(:member_role, :admin_protected_branch, namespace: group, members: [project_member])
      end

      it_behaves_like 'allows branch rule crud unless unprotect restrictions prevent',
        allowed: 'allows branch rule crud without squash options',
        restricted: 'disallows branch rule changes without squash options'

      context 'when custom_roles feature is not licensed' do
        let(:custom_roles_enabled) { false }

        it_behaves_like 'disallows branch rule crud'
      end
    end

    context 'with manage_merge_request_settings custom role' do
      before_all do
        create(:member_role, :manage_merge_request_settings, namespace: group, members: [project_member])
      end

      it { expect_allowed(:read_branch_rule) }
      it { expect_disallowed(:create_branch_rule) }
      it { expect_disallowed(:update_branch_rule) }
      it { expect_disallowed(:delete_branch_rule) }

      it_behaves_like 'allows squash option crud'

      context 'when custom_roles feature is not licensed' do
        let(:custom_roles_enabled) { false }

        it_behaves_like 'disallows branch rule crud'
      end
    end
  end
end
