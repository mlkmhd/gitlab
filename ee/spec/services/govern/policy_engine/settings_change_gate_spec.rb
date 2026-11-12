# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::SettingsChangeGate, feature_category: :security_policy_management do
  let_it_be(:group) do
    create(:group).tap { |group| group.namespace_settings.update!(policy_store_experiment_enabled: true) }
  end

  let_it_be(:project) { create(:project, :request_access_disabled, group: group) }
  let_it_be(:actor) { create(:user) }

  let(:organization) { project.organization }

  let!(:policy) do
    create(:govern_policy, :without_namespace, organization: organization,
      trigger_type: 'project.before_settings_update', mode: :enforce, name: 'Baseline',
      rules: [{ 'type' => 'setting_validation', 'rego' => 'package governance',
                'value' => { 'setting' => 'request_access_enabled', 'value' => false } }])
  end

  let(:params) { { request_access_enabled: '1' } }

  subject(:gate) { described_class.for_project(project: project, actor: actor, params: params) }

  before do
    stub_application_setting(policy_store_experiment_enabled: true)
    stub_licensed_features(security_orchestration_policies: true)
    stub_feature_flags(security_policies_v2: true)
  end

  def result_with(decisions:, verdict: :allow, policies: { policy.id => policy })
    Govern::PolicyEngine::EvaluateService::Result.new(
      verdict: verdict, decisions: decisions, identifier: 'x', error: nil, policies: policies)
  end

  def violating_decision(for_policy: policy, settings: ['request_access_enabled'], message: nil)
    {
      policy_id: for_policy.id,
      matched: true,
      error: nil,
      actions: [{ action_type: 'block', message: message, params: {}, gating: false }],
      reasons: settings.map do |setting|
        { message: 'violation', details: { 'path' => "project.settings.#{setting}",
                                           'expected' => false, 'actual' => true } }
      end
    }
  end

  def stub_evaluation(result)
    service = instance_double(Govern::PolicyEngine::EvaluateService, execute: result)
    allow(Govern::PolicyEngine::EvaluateService).to receive(:new)
      .with(hash_including(subject: project, trigger: 'project.before_settings_update'))
      .and_return(service)
  end

  it 'refuses a write that violates an enforce-mode block policy, naming the policy', :aggregate_failures do
    stub_evaluation(result_with(decisions: [violating_decision]))

    verdict = gate.execute

    expect(verdict.refusals).not_to be_empty
    expect(verdict.refusal_message).to eq("The setting request_access_enabled is locked by the policy 'Baseline'")
  end

  it 'passes a warn-mode policy through with the author message', :aggregate_failures do
    policy.update!(mode: :warn)
    stub_evaluation(result_with(decisions: [violating_decision]))

    verdict = gate.execute

    expect(verdict.refusals).to be_empty
    expect(verdict.warnings.sole).to include(policy: policy)
    expect(verdict.warnings.sole[:message]).to include('Baseline')
  end

  it 'prefers the block action message as the refusal message', :aggregate_failures do
    stub_evaluation(result_with(decisions: [violating_decision(message: 'Keep request access off.')]))

    verdict = gate.execute

    expect(verdict.refusals).not_to be_empty
    expect(verdict.refusal_message).to eq('Keep request access off.')
  end

  it 'prefers the block action message as the warn message' do
    policy.update!(mode: :warn)
    stub_evaluation(result_with(decisions: [violating_decision(message: 'Keep request access off.')]))

    verdict = gate.execute

    expect(verdict.warnings.sole[:message]).to eq('Keep request access off.')
  end

  it 'uses the default warn message when the decision carries no block action' do
    policy.update!(mode: :warn)
    stub_evaluation(result_with(decisions: [violating_decision.merge(actions: [])]))

    verdict = gate.execute

    expect(verdict.warnings.sole[:message]).to include('Baseline')
  end

  it 'ignores a decision that errored' do
    stub_evaluation(result_with(decisions: [violating_decision.merge(error: 'rego failed')]))

    expect(gate.execute.refusals).to be_empty
  end

  it 'does not block a save whose violation concerns a setting the write does not touch' do
    stub_evaluation(result_with(decisions: [violating_decision(settings: ['only_allow_merge_if_pipeline_succeeds'])]))

    expect(gate.execute.refusals).to be_empty
  end

  it 'does not refuse on a violation whose reason names no setting' do
    decision = violating_decision.merge(reasons: [{ message: 'custom rule violated', details: nil }])
    stub_evaluation(result_with(decisions: [decision]))

    expect(gate.execute.refusals).to be_empty
  end

  it 'fails open on an undecidable evaluation and reports it', :aggregate_failures do
    stub_evaluation(Govern::PolicyEngine::EvaluateService::Result.new(
      verdict: :undecidable, decisions: [], identifier: nil, error: 'store down', policies: {}))

    verdict = gate.execute

    expect(verdict.refusals).to be_empty
    expect(verdict.undecided).to be(true)
  end

  it 'keeps the refusals of decided policies when another policy is undecidable', :aggregate_failures do
    stub_evaluation(result_with(decisions: [violating_decision], verdict: :undecidable))

    verdict = gate.execute

    expect(verdict.refusal_message).to eq("The setting request_access_enabled is locked by the policy 'Baseline'")
    expect(verdict.undecided).to be(true)
  end

  it 'fails open when preparing the evaluation raises, tracking the exception', :aggregate_failures do
    allow(Govern::PolicyEngine::ProjectSettingsContext).to receive(:build).and_raise(StandardError, 'boom')
    expect(Govern::PolicyEngine::EvaluateService).not_to receive(:new)

    expect(Gitlab::ErrorTracking).to receive(:track_exception)
      .with(an_instance_of(StandardError), subject_id: project.id)

    verdict = gate.execute

    expect(verdict.refusals).to be_empty
    expect(verdict.undecided).to be(true)
  end

  it 'propagates a fault raised once the evaluation has run' do
    service = instance_double(Govern::PolicyEngine::EvaluateService)
    allow(service).to receive(:execute).and_raise(ActiveRecord::StatementInvalid, 'sec db down')
    allow(Govern::PolicyEngine::EvaluateService).to receive(:new).and_return(service)

    expect { gate.execute }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'passes without calling the engine when the write re-posts a drifted value unchanged' do
    drifted = create(:project, group: group, request_access_enabled: true)

    expect(Govern::PolicyEngine::EvaluateService).not_to receive(:new)

    expect(described_class.for_project(project: drifted, actor: actor, params: params).execute.refusals).to be_empty
  end

  it 'ignores a violation on a posted setting whose value does not change' do
    allow(Govern::PolicyEngine::EvaluateService).to receive(:new).and_return(instance_double(
      Govern::PolicyEngine::EvaluateService,
      execute: result_with(decisions: [violating_decision(settings: ['only_allow_merge_if_pipeline_succeeds'])])))

    verdict = described_class.for_project(project: project, actor: actor,
      params: { request_access_enabled: '1', only_allow_merge_if_pipeline_succeeds: '0' }).execute

    expect(verdict.refusals).to be_empty
  end

  it 'dispatches actions only for decisions whose violations touch a changed setting', :aggregate_failures do
    dispatch_if = nil
    allow(Govern::PolicyEngine::EvaluateService).to receive(:new) do |kwargs|
      dispatch_if = kwargs[:dispatch_if]
      instance_double(Govern::PolicyEngine::EvaluateService, execute: result_with(decisions: []))
    end

    gate.execute

    expect(dispatch_if.call(violating_decision)).to be(true)
    expect(dispatch_if.call(violating_decision(settings: ['squash_option']))).to be(false)
  end

  it 'passes untouched-governed writes without calling the engine', :aggregate_failures do
    expect(Govern::PolicyEngine::EvaluateService).not_to receive(:new)

    verdict = described_class.for_project(project: project, actor: actor, params: { name: 'renamed' }).execute

    expect(verdict.refusals).to be_empty
  end

  it 'ignores a decision naming a policy the result does not carry', :aggregate_failures do
    stub_evaluation(result_with(decisions: [violating_decision], policies: {}))

    verdict = gate.execute

    expect(verdict.refusals).to be_empty
    expect(verdict.warnings).to be_empty
  end

  it 'records nothing at the gate for an audit-mode policy', :aggregate_failures do
    policy.update!(mode: :audit)
    stub_evaluation(result_with(decisions: [violating_decision]))

    verdict = gate.execute

    expect(verdict.refusals).to be_empty
    expect(verdict.warnings).to be_empty
  end

  it 'passes when the experiment is disabled', :aggregate_failures do
    stub_application_setting(policy_store_experiment_enabled: false)

    expect(Govern::PolicyEngine::EvaluateService).not_to receive(:new)

    expect(gate.execute.refusals).to be_empty
  end

  it 'passes when neither the organization nor the group opted in to the experiment' do
    allow(group).to receive(:policy_store_experiment_enabled?).and_return(false)

    expect(Govern::PolicyEngine::EvaluateService).not_to receive(:new)

    expect(gate.execute.refusals).to be_empty
  end

  it 'overlays the proposed values onto the current context' do
    captured_context = nil
    allow(Govern::PolicyEngine::EvaluateService).to receive(:new) do |kwargs|
      captured_context = kwargs[:context]
      instance_double(Govern::PolicyEngine::EvaluateService, execute: result_with(decisions: []))
    end

    gate.execute

    expect(captured_context.dig('project', 'settings', 'request_access_enabled')).to be(true)
  end

  describe 'integration with Projects::UpdateService' do
    let_it_be_with_refind(:own_project) { create(:project, group: group, request_access_enabled: false) }

    def stub_project_evaluation(result)
      service = instance_double(Govern::PolicyEngine::EvaluateService, execute: result)
      allow(Govern::PolicyEngine::EvaluateService).to receive(:new)
        .with(hash_including(subject: own_project, trigger: 'project.before_settings_update'))
        .and_return(service)
    end

    it 'turns a refusal into an error result carrying the message', :aggregate_failures do
      stub_project_evaluation(result_with(decisions: [violating_decision]))

      result = Projects::UpdateService.new(own_project, actor, request_access_enabled: true).execute

      expect(result[:status]).to eq(:error)
      expect(result[:message]).to include("locked by the policy 'Baseline'")
      expect(own_project.errors[:base]).to contain_exactly(result[:message])
      expect(own_project.reload.read_attribute(:request_access_enabled)).to be(false)
    end

    it 'refuses before the default branch moves', :aggregate_failures do
      repo_project = create(:project, :repository, group: group, request_access_enabled: false)
      allow(Govern::PolicyEngine::EvaluateService).to receive(:new).and_return(
        instance_double(Govern::PolicyEngine::EvaluateService, execute: result_with(decisions: [violating_decision])))

      expect(repo_project).not_to receive(:change_head)

      result = Projects::UpdateService.new(repo_project, actor,
        request_access_enabled: true, default_branch: 'feature').execute

      expect(result[:status]).to eq(:error)
    end

    it 'fails open and lets the save through when preparing the evaluation raises', :aggregate_failures do
      allow(Govern::PolicyEngine::ProjectSettingsContext).to receive(:build).and_raise(StandardError)

      result = Projects::UpdateService.new(own_project, actor, request_access_enabled: true).execute

      expect(result[:status]).to eq(:success)
      expect(own_project.reload.read_attribute(:request_access_enabled)).to be(true)
    end

    it 'attaches warn messages to a successful result', :aggregate_failures do
      policy.update!(mode: :warn)
      stub_project_evaluation(result_with(decisions: [violating_decision]))

      result = Projects::UpdateService.new(own_project, actor, request_access_enabled: true).execute

      expect(result[:status]).to eq(:success)
      expect(result[:govern_warnings].sole).to include('Baseline')
      expect(own_project.reload.read_attribute(:request_access_enabled)).to be(true)
    end
  end
end
