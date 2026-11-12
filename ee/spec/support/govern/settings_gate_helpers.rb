# frozen_string_literal: true

module Govern
  module SettingsGateHelpers
    # Replaces the policy lookup and engine call behind SettingsChangeGate with
    # one matched decision, so a spec needs no stored policy.
    def stub_settings_gate_evaluation(policy:, setting:, expected:, actual:, message:)
      decision = {
        policy_id: policy.id, matched: true, error: nil,
        actions: [{ action_type: 'block', message: message, params: {}, gating: true }],
        reasons: [{ message: 'violation',
                    details: { 'path' => "project.settings.#{setting}", 'expected' => expected, 'actual' => actual } }]
      }
      result = Govern::PolicyEngine::EvaluateService::Result.new(
        verdict: :allow, decisions: [decision], identifier: 'x', error: nil, policies: { policy.id => policy })

      allow(Govern::PolicyEngine::EvaluateService).to receive(:new)
        .with(hash_including(trigger: 'project.before_settings_update'))
        .and_return(instance_double(Govern::PolicyEngine::EvaluateService, execute: result))
    end
  end
end
