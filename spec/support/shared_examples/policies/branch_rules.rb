# frozen_string_literal: true

RSpec.shared_examples 'allows squash option crud' do
  it { expect_allowed(:read_squash_option) }
  it { expect_allowed(:create_squash_option) }
  it { expect_allowed(:update_squash_option) }
  it { expect_allowed(:delete_squash_option) }
end

RSpec.shared_examples 'disallows squash option crud' do
  it { expect_disallowed(:read_squash_option) }
  it { expect_disallowed(:create_squash_option) }
  it { expect_disallowed(:update_squash_option) }
  it { expect_disallowed(:delete_squash_option) }
end

RSpec.shared_examples 'disallows squash option changes' do
  it { expect_allowed(:read_squash_option) }
  it { expect_disallowed(:create_squash_option) }
  it { expect_disallowed(:update_squash_option) }
  it { expect_disallowed(:delete_squash_option) }
end

RSpec.shared_examples 'allows branch rule crud without squash options' do
  it { expect_allowed(:read_branch_rule) }
  it { expect_allowed(:create_branch_rule) }
  it { expect_allowed(:update_branch_rule) }
  it { expect_allowed(:delete_branch_rule) }

  it_behaves_like 'disallows squash option crud'
end

RSpec.shared_examples 'disallows branch rule changes without squash options' do
  it { expect_allowed(:read_branch_rule) }
  it { expect_disallowed(:create_branch_rule) }
  it { expect_disallowed(:update_branch_rule) }
  it { expect_disallowed(:delete_branch_rule) }

  it_behaves_like 'disallows squash option crud'
end

RSpec.shared_examples 'allows branch rule crud' do
  it { expect_allowed(:read_branch_rule) }
  it { expect_allowed(:create_branch_rule) }
  it { expect_allowed(:update_branch_rule) }
  it { expect_allowed(:delete_branch_rule) }

  it_behaves_like 'allows squash option crud'
end

RSpec.shared_examples 'disallows branch rule crud' do
  it { expect_disallowed(:read_branch_rule) }
  it { expect_disallowed(:create_branch_rule) }
  it { expect_disallowed(:update_branch_rule) }
  it { expect_disallowed(:delete_branch_rule) }

  it_behaves_like 'disallows squash option crud'
end

RSpec.shared_examples 'disallows branch rule changes' do
  it { expect_allowed(:read_branch_rule) }
  it { expect_disallowed(:create_branch_rule) }
  it { expect_disallowed(:update_branch_rule) }
  it { expect_disallowed(:delete_branch_rule) }

  it_behaves_like 'disallows squash option changes'
end
