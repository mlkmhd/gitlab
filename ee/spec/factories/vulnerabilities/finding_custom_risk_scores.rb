# frozen_string_literal: true

FactoryBot.define do
  factory :vulnerability_finding_custom_risk_score, class: 'Vulnerabilities::FindingCustomRiskScore' do
    association :finding, factory: :vulnerabilities_finding

    project { finding.project }

    risk_score { 0.5 }
  end
end
