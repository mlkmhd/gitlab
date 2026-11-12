# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Policies::GroupProjectTransferWorker, '#perform', feature_category: :security_policy_management do
  let_it_be_with_reload(:top) { create(:group) }
  let_it_be_with_reload(:middle) { create(:group, parent: top) }
  let_it_be_with_reload(:bottom) { create(:group, parent: middle) }

  let_it_be_with_reload(:project) { create(:project, group: bottom) }
  let_it_be_with_reload(:merge_request) { create(:merge_request, target_project: project, source_project: project) }

  let_it_be_with_reload(:top_policy_configuration) do
    create(:security_orchestration_policy_configuration, :namespace, namespace: top)
  end

  let_it_be_with_reload(:middle_policy_configuration) do
    create(:security_orchestration_policy_configuration, :namespace, namespace: middle)
  end

  let_it_be_with_refind(:bottom_policy_configuration) do
    create(:security_orchestration_policy_configuration, :namespace, namespace: bottom)
  end

  let_it_be_with_refind(:project_policy_configuration) do
    create(:security_orchestration_policy_configuration, project: project)
  end

  let_it_be(:top_security_policy) do
    create(:security_policy, :require_approval, security_orchestration_policy_configuration: top_policy_configuration)
  end

  let_it_be(:middle_security_policy) do
    create(:security_policy, :require_approval,
      security_orchestration_policy_configuration: middle_policy_configuration)
  end

  let_it_be(:bottom_security_policy) do
    create(:security_policy, :require_approval,
      security_orchestration_policy_configuration: bottom_policy_configuration)
  end

  let_it_be(:project_security_policy) do
    create(:security_policy, :require_approval,
      security_orchestration_policy_configuration: project_policy_configuration)
  end

  let_it_be(:top_approval_rule) { create(:approval_policy_rule, security_policy: top_security_policy) }
  let_it_be(:middle_approval_rule) { create(:approval_policy_rule, security_policy: middle_security_policy) }
  let_it_be(:bottom_approval_rule) { create(:approval_policy_rule, security_policy: bottom_security_policy) }
  let_it_be(:project_approval_rule) { create(:approval_policy_rule, security_policy: project_security_policy) }

  let_it_be(:security_policy_bot) { create(:user, :security_policy_bot) }

  let(:project_id) { project.id }
  let(:current_user_id) { project.creator.id }

  subject(:perform) { described_class.new.perform(project_id, current_user_id) }

  before do
    allow_next_found_instances_of(Security::OrchestrationPolicyConfiguration, Float::INFINITY) do |config|
      allow(config).to receive(:policy_configuration_valid?).and_return(true)
    end

    Security::Policy.all.find_each do |policy|
      link_project(project, policy)
    end
  end

  before_all do
    project.add_guest(security_policy_bot)
    create(:protected_branch, project: project, name: merge_request.target_branch)
  end

  describe 'concurrency limit scope' do
    it 'caps each top-level group at a quarter of the concurrency limit' do
      expect(described_class.get_concurrency_limit_scope).to include(type: :root_namespace, max_percentage: 0.25)
    end

    describe 'enabled lambda' do
      subject(:enabled) { described_class.get_concurrency_limit_scope[:enabled].call }

      it { is_expected.to be(true) }

      context 'when group_project_transfer_worker_concurrency_limit_scope is disabled' do
        before do
          stub_feature_flags(group_project_transfer_worker_concurrency_limit_scope: false)
        end

        it { is_expected.to be(false) }
      end
    end
  end

  context 'with non-existent IDs' do
    shared_examples 'does not delete security policy links' do
      specify do
        expect { perform }.not_to change { project.security_policies.reload.to_a }
      end
    end

    shared_examples 'does not delete approval rules' do
      specify do
        expect { perform }.not_to change {
          merge_request.approval_rules.includes(:approval_policy_rule).reload.to_a.map(&:approval_policy_rule)
        }
      end
    end

    context 'with non-existent project ID' do
      let(:project_id) { non_existing_record_id }

      include_examples 'does not delete security policy links'
      include_examples 'does not delete approval rules'
    end

    context 'with non-existent user ID' do
      let(:user_id) { non_existing_record_id }

      include_examples 'does not delete security policy links'
      include_examples 'does not delete approval rules'
    end
  end

  context 'when applicable configurations have an invalid policy YAML' do
    before do
      allow_next_found_instances_of(Security::OrchestrationPolicyConfiguration, Float::INFINITY) do |config|
        allow(config).to receive(:policy_configuration_valid?).and_return(false)
      end
    end

    it 'does not delete security policy links' do
      expect { perform }.not_to change { project.security_policies.reload.to_a }
    end
  end

  describe 'moving to top-level' do
    before do
      bottom.update!(parent: nil)
    end

    it 'deletes security policy links' do
      expect { perform }.to change { project.security_policies.reload.to_a }
                              .from(contain_exactly(top_security_policy, middle_security_policy,
                                bottom_security_policy, project_security_policy))
                              .to(contain_exactly(bottom_security_policy, project_security_policy))
    end

    it 'deletes approval rules' do
      expect { perform }.to change {
        merge_request.approval_rules.includes(:approval_policy_rule).reload.to_a.map(&:approval_policy_rule)
      }
                              .from(contain_exactly(top_approval_rule, middle_approval_rule, bottom_approval_rule,
                                project_approval_rule))
                              .to(contain_exactly(bottom_approval_rule, project_approval_rule))
    end
  end

  describe 'moving up one level' do
    before do
      bottom.update!(parent: top)
    end

    it 'deletes security policy links' do
      expect { perform }.to change { project.security_policies.reload.to_a }
                              .from(contain_exactly(top_security_policy, middle_security_policy,
                                bottom_security_policy, project_security_policy))
                              .to(contain_exactly(top_security_policy, bottom_security_policy, project_security_policy))
    end

    it 'deletes approval rules' do
      expect { perform }.to change {
        merge_request.approval_rules.includes(:approval_policy_rule).reload.to_a.map(&:approval_policy_rule)
      }
                              .from(contain_exactly(top_approval_rule, middle_approval_rule, bottom_approval_rule,
                                project_approval_rule))
                              .to(contain_exactly(top_approval_rule, bottom_approval_rule, project_approval_rule))
    end
  end

  describe 'moving to other namespace' do
    let_it_be(:other_group) { create(:group) }
    let_it_be(:other_policy_configuration) do
      create(:security_orchestration_policy_configuration, :namespace, namespace: other_group)
    end

    let_it_be(:other_security_policy) do
      create(:security_policy, :require_approval,
        security_orchestration_policy_configuration: other_policy_configuration)
    end

    let_it_be(:other_approval_rule) { create(:approval_policy_rule, security_policy: other_security_policy) }

    let(:group_id) { middle.id }

    before do
      middle.update!(parent: other_group)

      unlink_project(project, other_security_policy)
    end

    it 'deletes security policy links' do
      expect { perform }.to change { project.security_policies.reload.to_a }
                              .from(contain_exactly(top_security_policy, middle_security_policy,
                                bottom_security_policy, project_security_policy))
                              .to(contain_exactly(other_security_policy, middle_security_policy,
                                bottom_security_policy, project_security_policy))
    end

    it 'deletes approval rules' do
      expect { perform }.to change {
        merge_request.approval_rules.includes(:approval_policy_rule).reload.to_a.map(&:approval_policy_rule)
      }
                              .from(contain_exactly(top_approval_rule, middle_approval_rule, bottom_approval_rule,
                                project_approval_rule))
                              .to(contain_exactly(other_approval_rule, middle_approval_rule, bottom_approval_rule,
                                project_approval_rule))
    end
  end

  context 'when project keeps approval rules from an unlinked configuration that no longer applies' do
    let_it_be(:stale_configuration) do
      create(:security_orchestration_policy_configuration, :namespace, namespace: create(:group))
    end

    let_it_be(:stale_read) do
      create(:scan_result_policy_read, security_orchestration_policy_configuration: stale_configuration,
        project: project)
    end

    let_it_be(:stale_approval_rule) do
      create(:approval_project_rule, :any_merge_request, :requires_approval, project: project,
        security_orchestration_policy_configuration: stale_configuration, scan_result_policy_read: stale_read)
    end

    let_it_be(:stale_merge_request_rule) do
      create(:report_approver_rule, :any_merge_request, merge_request: merge_request,
        security_orchestration_policy_configuration: stale_configuration, scan_result_policy_read: stale_read)
    end

    it 'deletes them', :aggregate_failures do
      perform

      expect(ApprovalProjectRule.exists?(stale_approval_rule.id)).to be(false)
      expect(Security::ScanResultPolicyRead.exists?(stale_read.id)).to be(false)
      expect(ApprovalMergeRequestRule.exists?(stale_merge_request_rule.id)).to be(false)
    end

    it 'keeps approval rules of configurations that still apply' do
      expect { perform }.not_to change {
        merge_request.approval_rules.id_not_in(stale_merge_request_rule.id).includes(:approval_policy_rule)
          .to_a.map(&:approval_policy_rule)
      }
    end

    context 'when feature flag `cleanup_inapplicable_policy_approval_rules` is disabled' do
      before do
        stub_feature_flags(cleanup_inapplicable_policy_approval_rules: false)
      end

      it 'keeps them', :aggregate_failures do
        perform

        expect(ApprovalProjectRule.exists?(stale_approval_rule.id)).to be(true)
        expect(Security::ScanResultPolicyRead.exists?(stale_read.id)).to be(true)
        expect(ApprovalMergeRequestRule.exists?(stale_merge_request_rule.id)).to be(true)
      end
    end
  end

  context 'when no policy configurations apply after move' do
    let_it_be(:other_group) { create(:group) }

    before do
      project_policy_configuration.delete
      bottom_policy_configuration.delete
      bottom.update!(parent: other_group)
    end

    it 'removes security policy bot' do
      expect(Security::OrchestrationConfigurationRemoveBotWorker).to receive(:perform_async).with(project.id,
        current_user_id)

      perform
    end

    it 'deletes security policy links' do
      expect { perform }.to change { project.security_policies.reload.to_a }
                              .from(contain_exactly(top_security_policy, middle_security_policy))
                              .to([])
    end

    it 'deletes approval rules' do
      expect { perform }.to change {
        merge_request.approval_rules.includes(:approval_policy_rule).reload.to_a.map(&:approval_policy_rule)
      }
                              .from(contain_exactly(top_approval_rule, middle_approval_rule))
                              .to([])
    end
  end

  private

  def link_project(project, policy)
    execute_change(project, policy, :link)
  end

  def unlink_project(project, policy)
    execute_change(project, policy, :unlink)
  end

  def execute_change(project, policy, action)
    Security::SecurityOrchestrationPolicies::LinkProjectService.new(
      project: project,
      security_policy: policy,
      action: action
    ).execute
  end
end
