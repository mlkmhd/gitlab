# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::JobArtifactPolicy, feature_category: :job_artifacts do
  let(:user) { build(:user) }
  let(:job_artifact) { build(:ci_job_artifact) }

  subject { described_class.new(user, job_artifact) }

  it { is_expected.to delegate_to(Authz::JobArtifactAccessPolicy) }

  # Some callers authorize Authz::JobArtifactAccess directly, so a rule here would not
  # apply to them. Add new conditions to Authz::JobArtifactAccessPolicy, and any new
  # attribute they read to Authz::JobArtifactAccess.
  it 'only delegates to the access subject' do
    expect(described_class.own_conditions).to be_empty
    expect(described_class.own_ability_map.map).to be_empty
    expect(described_class.own_global_actions).to be_empty
    expect(described_class.own_delegations.size).to eq(1)
  end

  describe '.preload_for_batch_checks' do
    let_it_be(:artifacts) do
      create_list(:project, 2).map do |project|
        create(:ci_job_artifact, :junit, job: create(:ci_build, project: project))
      end
    end

    it 'loads the jobs and projects the delegated subject reads' do
      records = Ci::JobArtifact.id_in(artifacts).to_a

      described_class.preload_for_batch_checks(records, user)

      expect { records.each { |artifact| [artifact.job.project, artifact.job.pipeline] } }
        .not_to exceed_query_limit(0)
    end
  end

  # End to end through the delegated subject, as the web download checks it
  describe 'read_job_artifacts for duo_workflow jobs' do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:public_project) { create(:project, :public) }
    let_it_be(:duo_workflow_job) do
      create(:ci_build, pipeline: create(:ci_pipeline, project: public_project, source: :duo_workflow))
    end

    let_it_be(:push_job) do
      create(:ci_build, pipeline: create(:ci_pipeline, project: public_project, source: :push))
    end

    let_it_be(:duo_workflow_junit) { create(:ci_job_artifact, :junit, job: duo_workflow_job) }
    let_it_be(:duo_workflow_sast) { create(:ci_job_artifact, :sast, job: duo_workflow_job) }
    let_it_be(:push_junit) { create(:ci_job_artifact, :junit, job: push_job) }

    let_it_be(:non_member) { create(:user) }
    let_it_be(:guest) { create(:user, guest_of: public_project) }
    let_it_be(:planner) { create(:user, planner_of: public_project) }
    let_it_be(:reporter) { create(:user, reporter_of: public_project) }
    let_it_be(:security_manager) { create(:user, security_manager_of: public_project) }
    let_it_be(:developer) { create(:user, developer_of: public_project) }
    let_it_be(:maintainer) { create(:user, maintainer_of: public_project) }
    let_it_be(:owner) { create(:user, owner_of: public_project) }

    where(:job_artifact, :user, :allowed) do
      ref(:duo_workflow_junit) | nil                    | false
      ref(:duo_workflow_junit) | ref(:non_member)       | false
      ref(:duo_workflow_junit) | ref(:guest)            | false
      ref(:duo_workflow_junit) | ref(:planner)          | false
      ref(:duo_workflow_junit) | ref(:reporter)         | false
      ref(:duo_workflow_junit) | ref(:security_manager) | false
      ref(:duo_workflow_junit) | ref(:developer)        | true
      ref(:duo_workflow_junit) | ref(:maintainer)       | true
      ref(:duo_workflow_junit) | ref(:owner)            | true
      ref(:duo_workflow_sast)  | nil                    | false
      ref(:duo_workflow_sast)  | ref(:reporter)         | false
      ref(:duo_workflow_sast)  | ref(:security_manager) | true
      ref(:duo_workflow_sast)  | ref(:developer)        | true
      ref(:push_junit)         | nil                    | true
      ref(:push_junit)         | ref(:non_member)       | true
      ref(:push_junit)         | ref(:guest)            | true
      ref(:push_junit)         | ref(:planner)          | true
      ref(:push_junit)         | ref(:reporter)         | true
      ref(:push_junit)         | ref(:security_manager) | true
      ref(:push_junit)         | ref(:developer)        | true
      ref(:push_junit)         | ref(:maintainer)       | true
      ref(:push_junit)         | ref(:owner)            | true
    end

    with_them do
      it { is_expected.to(allowed ? be_allowed(:read_job_artifacts) : be_disallowed(:read_job_artifacts)) }
    end

    context 'when user is an admin' do
      let_it_be(:user) { create(:admin) }
      let(:job_artifact) { duo_workflow_junit }

      context 'when admin mode is enabled', :enable_admin_mode do
        it { expect_allowed(:read_job_artifacts) }
      end

      context 'when admin mode is disabled' do
        it { expect_disallowed(:read_job_artifacts) }
      end
    end
  end
end
