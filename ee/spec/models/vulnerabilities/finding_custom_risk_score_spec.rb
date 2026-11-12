# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::FindingCustomRiskScore, feature_category: :vulnerability_management do
  describe 'associations' do
    it { is_expected.to belong_to(:finding).required }
    it { is_expected.to belong_to(:project).required }
  end

  describe 'validations' do
    subject { build(:vulnerability_finding_custom_risk_score) }

    it { is_expected.to validate_presence_of(:risk_score) }
    it { is_expected.to validate_uniqueness_of(:vulnerability_occurrence_id) }

    it 'validates risk_score is between 0.0 and 1.0' do
      is_expected.to validate_numericality_of(:risk_score)
        .is_greater_than_or_equal_to(0.0)
        .is_less_than_or_equal_to(1.0)
    end

    it 'is invalid when project does not match finding project' do
      finding = create(:vulnerabilities_finding)
      other_project = create(:project)

      record = build(
        :vulnerability_finding_custom_risk_score,
        finding: finding,
        project: other_project
      )

      expect(record).to be_invalid
      expect(record.errors[:project_id]).to be_present
    end
  end
end
