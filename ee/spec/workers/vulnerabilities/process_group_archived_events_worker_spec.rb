# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::ProcessGroupArchivedEventsWorker, feature_category: :vulnerability_management, type: :job do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:nested_subgroup) { create(:group, parent: subgroup) }

  let_it_be(:vulnerable_project) { create(:project, :with_vulnerability, group: group) }
  let_it_be(:project_without_vulnerabilities) { create(:project, group: group) }
  let_it_be(:nested_vulnerable_project) { create(:project, :with_vulnerability, group: nested_subgroup) }
  let_it_be(:nested_project_without_vulnerabilities) { create(:project, group: nested_subgroup) }
  let_it_be(:project_without_settings) do
    create(:project, :with_vulnerability, group: group).tap { |project| project.project_setting.delete }
  end

  let_it_be(:project_with_setting_only) do
    create(:project, group: group).tap { |project| project.project_setting.update!(has_vulnerabilities: true) }
  end

  let_it_be(:pending_delete_vulnerable_project) do
    create(:project, :with_vulnerability, group: group, pending_delete: true)
  end

  let(:archived_group) { group }
  let(:root_namespace_id) { group.id }
  let(:event) do
    ::Namespaces::Groups::GroupArchivedEvent.new(data: {
      group_id: archived_group.id,
      root_namespace_id: root_namespace_id
    })
  end

  let(:projects_with_vulnerabilities_setting) do
    [vulnerable_project, nested_vulnerable_project, project_with_setting_only, pending_delete_vulnerable_project]
  end

  let(:all_projects) do
    projects_with_vulnerabilities_setting +
      [project_without_vulnerabilities, nested_project_without_vulnerabilities, project_without_settings]
  end

  let(:reads_worker) { Vulnerabilities::UpdateArchivedAttributeOfVulnerabilityReadsWorker }
  let(:statistics_worker) { Vulnerabilities::UpdateArchivedAttributeOfVulnerabilityStatisticsWorker }
  let(:scheduled) { Hash.new { |hash, worker| hash[worker] = { ids: [], contexts: [] } } }

  subject(:use_event) { consume_event(subscriber: described_class, event: event) }

  before do
    [reads_worker, statistics_worker].each do |worker|
      allow(worker).to receive(:bulk_perform_async_with_contexts) do |projects, arguments_proc:, context_proc:|
        scheduled[worker][:ids].concat(projects.map(&arguments_proc))
        scheduled[worker][:contexts].concat(projects.map(&context_proc))
      end
    end
  end

  it_behaves_like 'worker with data consistency', described_class, data_consistency: :always

  shared_examples 'schedules both workers for' do
    it 'schedules the vulnerability reads and statistics workers with project ids and contexts', :aggregate_failures do
      use_event

      [reads_worker, statistics_worker].each do |worker|
        expect(scheduled[worker][:ids]).to match_array(expected_projects.map(&:id))
        expect(scheduled[worker][:contexts]).to match_array(expected_projects.map { |project| { project: project } })
      end
    end
  end

  shared_examples 'schedules no per-project jobs' do
    it 'does not schedule the vulnerability reads and statistics workers for any project', :aggregate_failures do
      use_event

      expect(scheduled[reads_worker][:ids]).to be_empty
      expect(scheduled[statistics_worker][:ids]).to be_empty
    end
  end

  it_behaves_like 'schedules both workers for' do
    let(:expected_projects) { projects_with_vulnerabilities_setting }
  end

  it 'schedules Namespace Statistics recalculation worker for the group' do
    expect(Vulnerabilities::NamespaceStatistics::RecalculateNamespaceStatisticsWorker)
      .to receive(:perform_in)
      .with(6.hours, group.id)

    use_event
  end

  it 'checks the feature flag once per event, with the archived group as the actor', :aggregate_failures do
    stub_const("#{described_class}::BATCH_SIZE", 1)
    allow(Feature).to receive(:enabled?).and_call_original

    use_event

    expect(Feature).to have_received(:enabled?)
      .with(
        :skip_group_archive_jobs_for_projects_without_vulnerabilities,
        having_attributes(flipper_id: "Group:#{group.id}")
      )
      .once
    expect(scheduled[reads_worker][:ids]).to match_array(projects_with_vulnerabilities_setting.map(&:id))
  end

  it 'keeps the number of queries constant as projects are added' do
    # Warm up caches so the control counts only the queries each event runs.
    consume_event(subscriber: described_class, event: event)
    control = ActiveRecord::QueryRecorder.new { consume_event(subscriber: described_class, event: event) }

    create(:project, :with_vulnerability, group: group)
    create(:project, group: nested_subgroup)

    expect { use_event }.not_to exceed_query_limit(control)
  end

  context 'when the group has projects only in subgroups' do
    let_it_be(:parent_only_group) { create(:group) }
    let_it_be(:child_group) { create(:group, parent: parent_only_group) }
    let_it_be(:child_vulnerable_project) { create(:project, :with_vulnerability, group: child_group) }

    let(:archived_group) { parent_only_group }
    let(:root_namespace_id) { parent_only_group.id }

    it_behaves_like 'schedules both workers for' do
      let(:expected_projects) { [child_vulnerable_project] }
    end
  end

  context 'when no project in the group has vulnerabilities' do
    let_it_be(:group_without_vulnerabilities) { create(:group) }
    let_it_be(:project_in_group_without_vulnerabilities) { create(:project, group: group_without_vulnerabilities) }

    let(:archived_group) { group_without_vulnerabilities }
    let(:root_namespace_id) { group_without_vulnerabilities.id }

    it_behaves_like 'schedules no per-project jobs'
  end

  context 'when the group has no projects and no subgroups' do
    let_it_be(:empty_group) { create(:group) }

    let(:archived_group) { empty_group }
    let(:root_namespace_id) { empty_group.id }

    it_behaves_like 'schedules no per-project jobs'

    it 'still schedules the namespace statistics recalculation' do
      expect(Vulnerabilities::NamespaceStatistics::RecalculateNamespaceStatisticsWorker)
        .to receive(:perform_in).with(6.hours, empty_group.id)

      use_event
    end
  end

  context 'when the group no longer exists' do
    let(:event) do
      ::Namespaces::Groups::GroupArchivedEvent.new(data: {
        group_id: non_existing_record_id,
        root_namespace_id: non_existing_record_id
      })
    end

    it_behaves_like 'schedules no per-project jobs'
  end

  context 'when the feature flag is enabled for another group only' do
    before do
      stub_feature_flags(skip_group_archive_jobs_for_projects_without_vulnerabilities: create(:group))
    end

    it_behaves_like 'schedules both workers for' do
      let(:expected_projects) { all_projects }
    end
  end

  context 'when the feature flag is enabled for the root group only and the event is for a subgroup' do
    let(:archived_group) { subgroup }

    before do
      stub_feature_flags(skip_group_archive_jobs_for_projects_without_vulnerabilities: group)
    end

    it_behaves_like 'schedules both workers for' do
      let(:expected_projects) { [nested_vulnerable_project, nested_project_without_vulnerabilities] }
    end
  end

  context 'when the feature flag is enabled for the archived subgroup but not its root group' do
    let(:archived_group) { subgroup }

    before do
      stub_feature_flags(skip_group_archive_jobs_for_projects_without_vulnerabilities: subgroup)
    end

    it_behaves_like 'schedules both workers for' do
      let(:expected_projects) { [nested_vulnerable_project] }
    end
  end

  context 'when skip_group_archive_jobs_for_projects_without_vulnerabilities is disabled' do
    before do
      stub_feature_flags(skip_group_archive_jobs_for_projects_without_vulnerabilities: false)
    end

    it_behaves_like 'schedules both workers for' do
      let(:expected_projects) { all_projects }
    end
  end
end
