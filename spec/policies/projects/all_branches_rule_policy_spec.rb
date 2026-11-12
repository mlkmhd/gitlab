# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::AllBranchesRulePolicy, feature_category: :source_code_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }

  let(:branch_rule) { Projects::AllBranchesRule.new(project) }

  subject(:policy) { described_class.new(user, branch_rule) }

  it { is_expected.to delegate_to(ProjectPolicy) }

  context 'as a maintainer' do
    before_all do
      project.add_maintainer(user)
    end

    it { expect_allowed(:read_branch_rule) }
    it { expect_disallowed(:create_branch_rule) }
    it { expect_disallowed(:update_branch_rule) }
    it { expect_disallowed(:delete_branch_rule) }

    it_behaves_like 'allows squash option crud'
  end
end
