# frozen_string_literal: true

module Govern
  # Evaluates setting_validation rules in Ruby, in place of the glaz engine
  # behind Gitlab::Glaz::GovernPolicyEngine#evaluate, so a spec can drive the
  # real host chain with only that one boundary replaced. A rule the engine
  # would compile to raw Rego raises here instead of passing unnoticed.
  class FakeGlazEngine
    UnsupportedRule = Class.new(StandardError)

    # The policies stand in for what the policy store would return, so the
    # engine reads none itself. A spec adds the ones the store would serve.
    attr_reader :policies

    def initialize(policies: [])
      @policies = policies
    end

    # principal, resource and store_authorization are accepted to honor the
    # gem's calling contract, which this double itself does not need.
    def evaluate(trigger:, context:, resource: nil, principal: nil, store_authorization: nil) # rubocop:disable Lint/UnusedMethodArgument -- gem contract
      decisions = policies.select { |policy| policy.trigger_type == trigger }.map do |policy|
        decision_for(policy, context)
      end

      { decisions: decisions, undecided_policy_ids: [], identifier: SecureRandom.uuid }
    end

    private

    def decision_for(policy, context)
      reasons = policy.rules.each_with_index.filter_map do |rule, index|
        reason_for(rule, index, context)
      end

      {
        policy_id: policy.id,
        matched: reasons.any?,
        error: nil,
        actions: policy.actions.to_a.map { |action| decision_action(action) },
        reasons: reasons
      }
    end

    def reason_for(rule, index, context)
      unless rule['type'] == 'setting_validation'
        raise UnsupportedRule, "FakeGlazEngine only evaluates setting_validation rules, got #{rule['type'].inspect}"
      end

      setting = rule.dig('value', 'setting')
      expected = rule.dig('value', 'value')
      actual = context.dig('project', 'settings', setting)

      # Mirrors the emitted Rego's `actual != null` guard: an absent setting
      # is not enforceable on the subject, so it is skipped, not violated.
      return if actual.nil?
      return if actual == expected

      {
        message: "setting #{setting} must be #{expected}",
        details: { 'rule_index' => index, 'path' => "project.settings.#{setting}",
                   'expected' => expected, 'actual' => actual }
      }
    end

    def decision_action(action)
      {
        action_type: action['type'],
        message: action.dig('value', 'message'),
        params: action['value'] || {},
        gating: action['type'] == 'block'
      }
    end
  end

  module FakeGlazEngineHelpers
    # EvaluateService routes every engine call through its class-level
    # .engine, so this one seam covers the gate and both workers.
    def stub_govern_glaz_engine
      engine = Govern::FakeGlazEngine.new
      allow(Govern::PolicyEngine::EvaluateService).to receive(:engine).and_return(engine)
      engine
    end
  end
end
