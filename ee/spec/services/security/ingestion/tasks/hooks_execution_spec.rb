# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Ingestion::Tasks::HooksExecution, feature_category: :vulnerability_management do
  describe '#execute' do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:pipeline) { create(:ci_pipeline) }
    let_it_be(:tracked_context) do
      create(:security_project_tracked_context, :default, :tracked, project: pipeline.project)
    end

    let_it_be(:non_default_tracked_context) do
      create(:security_project_tracked_context, :tracked, context_name: 'dev', project: pipeline.project)
    end

    let_it_be(:non_default_untracked_context) do
      create(:security_project_tracked_context, :untracked, context_name: 'wip', project: pipeline.project)
    end

    let_it_be(:tag_tracked_context) do
      create(:security_project_tracked_context, :tag, :tracked, project: pipeline.project)
    end

    let_it_be(:vulnerabilities) { create_list(:vulnerability, 9) }

    let_it_be(:finding_map_1) do
      create(:finding_map, vulnerability: vulnerabilities[0], tracked_context: tracked_context, new_record: true)
    end

    let_it_be(:finding_map_2) do
      create(:finding_map, vulnerability: vulnerabilities[1], tracked_context: tracked_context, new_record: true)
    end

    let_it_be(:finding_map_3) do
      create(:finding_map, vulnerability: vulnerabilities[2], tracked_context: tracked_context)
    end

    let_it_be(:finding_map_4) do
      create(:finding_map, vulnerability: vulnerabilities[3],
        tracked_context: non_default_tracked_context, new_record: true)
    end

    let_it_be(:finding_map_5) do
      create(:finding_map, vulnerability: vulnerabilities[4],
        tracked_context: non_default_untracked_context, new_record: true)
    end

    let_it_be(:finding_map_6) do
      create(:finding_map, vulnerability: vulnerabilities[5],
        tracked_context: tag_tracked_context, new_record: true)
    end

    let_it_be(:finding_map_7) do
      create(:finding_map, vulnerability: vulnerabilities[6],
        report_finding: build(:ci_reports_security_finding, report_type: :secret_detection),
        tracked_context: non_default_tracked_context, new_record: true)
    end

    let_it_be(:finding_map_8) do
      create(:finding_map, vulnerability: vulnerabilities[7],
        report_finding: build(:ci_reports_security_finding, report_type: :secret_detection),
        tracked_context: tag_tracked_context, new_record: true)
    end

    let_it_be(:finding_map_9) do
      create(:finding_map, vulnerability: vulnerabilities[8],
        report_finding: build(:ci_reports_security_finding, report_type: :dependency_scanning),
        tracked_context: non_default_tracked_context, new_record: true)
    end

    let(:hooked_ids) { [] }
    let(:fp_triggered_ids) { [] }

    let!(:service_object) do
      described_class.new(task_pipeline,
        [finding_map_1, finding_map_2, finding_map_3, finding_map_4, finding_map_5, finding_map_6,
          finding_map_7, finding_map_8, finding_map_9])
    end

    subject(:ingest_finding_remediations) { service_object.execute }

    before do
      vulnerabilities.each do |vulnerability|
        allow(vulnerability).to receive(:execute_hooks) { hooked_ids << vulnerability.id }
        allow(vulnerability).to receive(:trigger_false_positive_detection) { fp_triggered_ids << vulnerability.id }
      end

      allow(Security::VAC).to receive(:enabled?).with(pipeline.project).and_return(vac_enabled)
      stub_feature_flags(
        fp_detection_non_default_branches: non_default_branches_flag,
        secrets_fp_detection_non_default_branches: secrets_non_default_branches_flag
      )

      allow(Vulnerability).to receive(:id_in).and_wrap_original do |original, ids|
        original.call(ids).tap do |relation|
          allow(relation).to receive(:with_projects).and_return(vulnerabilities.select { |v| v.id.in?(ids) })
        end
      end

      SecApplicationRecord.transaction { ingest_finding_remediations }
    end

    # Indexes: 0-1 new on default branch, 2 existing, 3 SAST on tracked non-default branch, 4 untracked branch,
    # 5 tracked tag, 6/7 secrets on tracked non-default branch/tag, 8 dependency scanning on tracked non-default branch.
    # A nil pipeline is how CVS ingestion runs this task.
    where(:task_pipeline, :vac_enabled, :non_default_branches_flag, :secrets_non_default_branches_flag,
      :expected_indexes) do
      ref(:pipeline) | false | false | false | [0, 1]
      ref(:pipeline) | true  | false | false | [0, 1]
      ref(:pipeline) | false | true  | true  | [0, 1]
      ref(:pipeline) | true  | true  | false | [0, 1, 3, 5]
      ref(:pipeline) | true  | false | true  | [0, 1, 6, 7]
      ref(:pipeline) | true  | true  | true  | [0, 1, 3, 5, 6, 7]
      nil            | false | false | false | [0, 1]
      nil            | true  | true  | true  | [0, 1, 3, 5, 6, 7]
    end

    with_them do
      it 'executes hooks and triggers false positive detection only for eligible new vulnerabilities' do
        expected_ids = vulnerabilities.values_at(*expected_indexes).map(&:id)

        expect(hooked_ids).to match_array(expected_ids)
        expect(fp_triggered_ids).to match_array(expected_ids)
      end
    end
  end

  describe 'false positive detection for vulnerabilities promoted to the default branch' do
    let_it_be(:project) { create(:project, duo_sast_fp_detection_enabled: true) }
    let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
    let_it_be(:tracked_context) do
      create(:security_project_tracked_context, :default, :tracked, project: project)
    end

    before do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(anything, :duo_workflow, project).and_return(true)
    end

    # Acting on a merge request security finding creates its vulnerability off the default branch.
    # The default branch pipeline then promotes it, which is what `SetPresentOnDefaultBranch` does.
    def create_and_promote(state)
      vulnerability = create(:vulnerability, :sast, :critical, :with_finding, state, project: project,
        present_on_default_branch: false)
      vulnerability.update!(present_on_default_branch: true)
      finding_map = create(:finding_map, vulnerability: vulnerability, tracked_context: tracked_context,
        new_record: true)

      SecApplicationRecord.transaction { described_class.new(pipeline, [finding_map]).execute }
    end

    it 'triggers false positive detection once, when a detected vulnerability is promoted' do
      expect(::Vulnerabilities::TriggerFalsePositiveDetectionWorkflowWorker).to receive(:perform_async).once

      create_and_promote(:detected)
    end

    it 'does not trigger false positive detection when a dismissed vulnerability is promoted' do
      expect(::Vulnerabilities::TriggerFalsePositiveDetectionWorkflowWorker).not_to receive(:perform_async)

      create_and_promote(:dismissed)
    end
  end

  describe 'project preloading' do
    let_it_be(:project) { create(:project) }
    let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
    let_it_be(:tracked_context) do
      create(:security_project_tracked_context, :default, :tracked, project: project)
    end

    def build_finding_maps(count)
      create_list(:vulnerability, count, :sast, project: project).map do |vulnerability|
        create(:finding_map, vulnerability: vulnerability, tracked_context: tracked_context, new_record: true)
      end
    end

    def ingest(finding_maps)
      SecApplicationRecord.transaction { described_class.new(pipeline, finding_maps).execute }
    end

    # Eligibility reads project_setting, and `root_ancestor`, which loads namespace.
    it 'avoids N+1 database queries', :aggregate_failures do
      one_finding_map = build_finding_maps(1)
      many_finding_maps = build_finding_maps(3)

      control = ActiveRecord::QueryRecorder.new { ingest(one_finding_map) }

      expect { ingest(many_finding_maps) }.not_to exceed_query_limit(control).for_model(ProjectSetting)
      expect { ingest(many_finding_maps) }
        .not_to exceed_query_limit(control).for_query(/find_namespaces_by_id/)
    end
  end
end
