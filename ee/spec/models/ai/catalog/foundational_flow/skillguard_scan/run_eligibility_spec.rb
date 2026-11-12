# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::SkillguardScan::RunEligibility, :clean_gitlab_redis_shared_state,
  feature_category: :duo_agent_platform do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, group: group) }
  let_it_be(:pipeline) { create(:ci_pipeline, :success, project: project, ref: project.default_branch) }

  let(:resource) { pipeline }

  subject(:eligible) { described_class.call(project: project, resource: resource) }

  before do
    stub_licensed_features(security_scan_profiles: true)
    stub_feature_flags(skillguard_analyzer: group)
    allow(::Gitlab::AppJsonLogger).to receive(:info)
  end

  def attach_profile(trigger_type, scan_type: :skillguard)
    profile = create(:security_scan_profile, namespace: group, scan_type: scan_type, projects: [project])
    create(:security_scan_profile_trigger, scan_profile: profile, trigger_type: trigger_type)
  end

  shared_examples 'a skipped run' do |reason|
    it 'returns false and logs why', :aggregate_failures do
      expect(eligible).to be(false)
      expect(::Gitlab::AppJsonLogger).to have_received(:info).with(hash_including(
        message: "Skipping SkillGuard scan flow: #{reason}", project_id: project.id, pipeline_id: resource&.id
      ))
    end
  end

  # A pipeline skipped before its profile is attached must still be scanned on a retried job.
  shared_examples 'a skip that leaves the pipeline free' do
    it 'does not take the lease' do
      eligible

      expect(::Gitlab::ExclusiveLease.new(described_class.lease_key(resource), timeout: 1).exists?).to be(false)
    end
  end

  it_behaves_like 'a skipped run', 'no SkillGuard scan profile attached for default branch pipelines'
  it_behaves_like 'a skip that leaves the pipeline free'

  context 'when only another scan type has a default branch trigger' do
    before do
      attach_profile(:default_branch_pipeline, scan_type: :sast)
    end

    it_behaves_like 'a skipped run', 'no SkillGuard scan profile attached for default branch pipelines'
  end

  context 'when the SkillGuard profile triggers on default branch pipelines' do
    before do
      attach_profile(:default_branch_pipeline)
    end

    it { is_expected.to be(true) }

    context 'when the pipeline already started a run' do
      before do
        described_class.call(project: project, resource: resource)
      end

      it_behaves_like 'a skipped run', 'pipeline already scanned'

      context 'when the run was released' do
        before do
          described_class.release(resource)
        end

        it { is_expected.to be(true) }
      end
    end

    context 'when the project is not licensed for scan profiles' do
      before do
        stub_licensed_features(security_scan_profiles: false)
      end

      it_behaves_like 'a skipped run', 'no SkillGuard scan profile attached for default branch pipelines'
      it_behaves_like 'a skip that leaves the pipeline free'
    end

    context 'when skillguard_analyzer is disabled for the top-level group' do
      before do
        stub_feature_flags(skillguard_analyzer: false)
      end

      it_behaves_like 'a skipped run', 'skillguard_analyzer is disabled'
      it_behaves_like 'a skip that leaves the pipeline free'
    end

    context 'when the project is in a subgroup' do
      let_it_be(:subgroup) { create(:group, parent: group) }
      let_it_be(:project) { create(:project, :repository, group: subgroup) }
      let_it_be(:pipeline) { create(:ci_pipeline, :success, project: project, ref: project.default_branch) }

      it { is_expected.to be(true) }
    end

    context 'when the pipeline is gone' do
      let(:resource) { nil }

      it_behaves_like 'a skipped run', 'pipeline not found'
    end
  end
end
