# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::ConflictedSettings, feature_category: :security_policy_management do
  let(:write_action) { { action_type: 'set_setting', gating: false } }

  def policy_demanding(expected, mode: :enforce, setting: 'request_access_enabled')
    build_stubbed(:govern_policy, mode: mode,
      rules: [{ 'type' => 'setting_validation', 'value' => { 'setting' => setting, 'value' => expected } }])
  end

  def decision_for(policy, actions: [{ action_type: 'set_setting', gating: false }], matched: true, error: nil)
    { policy_id: policy.id, matched: matched, error: error, actions: actions }
  end

  def conflicts(*policies, **overrides)
    decisions = policies.map { |policy| decision_for(policy, **overrides) }

    described_class.for(decisions: decisions, policies: policies.index_by(&:id))
  end

  it 'conflicts a setting two enforce policies demand different values for, naming each demand' do
    first = policy_demanding(false)
    second = policy_demanding(true)

    expect(conflicts(first, second)).to eq('request_access_enabled' => { first.id => false, second.id => true })
  end

  it 'does not conflict when the policies agree' do
    expect(conflicts(policy_demanding(false), policy_demanding(false))).to be_empty
  end

  it 'ignores a policy that does not enforce' do
    expect(conflicts(policy_demanding(false), policy_demanding(true, mode: :warn))).to be_empty
  end

  it 'counts a policy the project already complies with, since it still demands its value' do
    first = policy_demanding(false)
    second = policy_demanding(true)
    decisions = [decision_for(first), decision_for(second, matched: false)]

    expect(described_class.for(decisions: decisions, policies: [first, second].index_by(&:id)))
      .to eq('request_access_enabled' => { first.id => false, second.id => true })
  end

  it 'counts a policy whose evaluation failed, since its demand is in the stored rule' do
    expect(conflicts(policy_demanding(false), policy_demanding(true), error: 'rego broke')).not_to be_empty
  end

  it 'does not conflict numeric values that differ only in type' do
    expect(conflicts(policy_demanding(1, setting: 'max_artifacts_size'),
      policy_demanding(1.0, setting: 'max_artifacts_size'))).to be_empty
  end

  it 'ignores a decision carrying no write action, which cannot oscillate a value' do
    expect(conflicts(policy_demanding(false), policy_demanding(true),
      actions: [{ action_type: 'log_audit_trail', gating: false }])).to be_empty
  end

  it 'keeps settings apart' do
    first = policy_demanding(false)
    second = policy_demanding(true, setting: 'squash_option')

    expect(conflicts(first, second)).to be_empty
  end

  it 'ignores a decision whose policy is unknown locally' do
    policy = policy_demanding(false)
    decisions = [decision_for(policy), { policy_id: non_existing_record_id, matched: true, error: nil,
                                         actions: [write_action] }]

    expect(described_class.for(decisions: decisions, policies: { policy.id => policy })).to be_empty
  end
end
