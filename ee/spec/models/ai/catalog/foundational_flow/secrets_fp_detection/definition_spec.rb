# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::SecretsFpDetection::Definition, feature_category: :duo_agent_platform do
  subject(:flow) { Ai::Catalog::FoundationalFlow.secrets_fp_detection_v1 }

  it_behaves_like 'flow with additional context resolver',
    resolver: Ai::Catalog::FoundationalFlow::SecretsFpDetection::Context,
    envelope_alias: 'secret_detection_context'

  it 'disallows event triggers' do
    expect(flow.supported_events).to eq([])
  end

  describe 'source branch resolution' do
    let_it_be(:project) { create(:project) }
    let_it_be(:tracked_context) do
      create(:security_project_tracked_context, :tracked, project: project, context_name: 'feature-branch')
    end

    let_it_be(:vulnerability) do
      create(:vulnerability, :secret_detection, :with_finding, project: project).tap do |vulnerability|
        vulnerability.finding.update!(project_tracked_context: tracked_context)
      end
    end

    subject(:source_branch) { flow.resolve_source_branch_for(project: project, goal: vulnerability.id.to_s) }

    before do
      allow(Security::VAC).to receive(:enabled?).and_return(true)
    end

    it 'resolves the source branch with VulnerabilitySourceBranchResolver' do
      expect(flow.source_branch_resolver).to eq(Ai::Catalog::FoundationalFlow::VulnerabilitySourceBranchResolver)
    end

    it { is_expected.to eq('feature-branch') }

    context 'when the secrets_fp_detection_non_default_branches flag is disabled' do
      before do
        stub_feature_flags(secrets_fp_detection_non_default_branches: false)
      end

      it { is_expected.to be_nil }
    end
  end
end
