# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ProtectedEnvironmentApprovalRuleForSummary'],
  feature_category: :deployment_management do
  specify { expect(described_class.graphql_name).to eq('ProtectedEnvironmentApprovalRuleForSummary') }

  it 'includes the expected fields' do
    expected_fields = %w[
      approvals
      approved_count
      can_approve
      pending_approval_count
      required_approvals
      status
    ]

    expect(described_class).to include_graphql_fields(*expected_fields)
  end

  it 'requires read_protected_environment on the project or group of the protected environment' do
    directives = described_class.directives.select { |d| d.is_a?(::Directives::Authz::GranularScope) }

    expect(directives.map { |d| d.arguments.to_h.slice(:permissions, :boundary, :boundary_type) }).to contain_exactly(
      { permissions: %w[read_protected_environment], boundary: 'protected_environment_project',
        boundary_type: 'project' },
      { permissions: %w[read_protected_environment], boundary: 'protected_environment_group', boundary_type: 'group' }
    )
  end

  describe '#can_approve' do
    include_context 'with an approval rule and approver'

    subject(:result) do
      described_class.send(
        :new, approval_rule, { current_user: user_being_checked }
      ).can_approve
    end

    context 'when user can approve' do
      let_it_be(:user_being_checked) { approver }

      it { is_expected.to be(true) }
    end

    context 'when user cannot approve' do
      include_context 'with a non approver'

      let_it_be(:user_being_checked) { non_approver }

      it { is_expected.to be(false) }
    end

    context 'when user is nil' do
      let_it_be(:user_being_checked) { nil }

      it { is_expected.to be(false) }
    end
  end
end
