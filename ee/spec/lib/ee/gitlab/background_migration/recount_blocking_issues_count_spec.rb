# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::RecountBlockingIssuesCount, feature_category: :portfolio_management do
  let(:opened_state_id) { 1 }
  let(:closed_state_id) { 2 }
  let(:relates_to_link_type) { 0 }
  let(:blocks_link_type) { 1 }

  let(:namespaces) { table(:namespaces) }
  let(:issues) { table(:issues) }
  let(:issue_links) { table(:issue_links) }

  let!(:organization) { table(:organizations).create!(name: 'organization', path: 'organization') }
  let!(:group) { namespaces.create!(name: 'group', path: 'group', type: 'Group', organization_id: organization.id) }
  let!(:project_namespace) do
    namespaces.create!(
      name: 'project', path: 'project', type: 'Project', parent_id: group.id, organization_id: organization.id
    )
  end

  let!(:project) do
    table(:projects).create!(
      namespace_id: group.id, project_namespace_id: project_namespace.id, organization_id: organization.id
    )
  end

  it 'lowers a count left too high to the open issues still blocked' do
    blocker = create_issue(blocking_issues_count: 3)
    link(blocker, create_issue)
    link(blocker, create_issue(state_id: closed_state_id))

    expect { perform_migration }.to change { blocker.reload.blocking_issues_count }.from(3).to(1)
  end

  it 'sets the count to 0 when no blocks link is left' do
    blocker = create_issue(blocking_issues_count: 2)

    expect { perform_migration }.to change { blocker.reload.blocking_issues_count }.from(2).to(0)
  end

  it 'sets the count to 0 when every blocked issue is closed' do
    blocker = create_issue(blocking_issues_count: 1)
    link(blocker, create_issue(state_id: closed_state_id))

    expect { perform_migration }.to change { blocker.reload.blocking_issues_count }.from(1).to(0)
  end

  it 'counts neither related issues nor the issues an issue is blocked by' do
    issue = create_issue(blocking_issues_count: 2)
    link(issue, create_issue, link_type: relates_to_link_type)
    link(create_issue(blocking_issues_count: 1), issue)

    expect { perform_migration }.to change { issue.reload.blocking_issues_count }.from(2).to(0)
  end

  it 'recounts every blocker across sub-batches', :aggregate_failures do
    blockers = Array.new(3) { create_issue(blocking_issues_count: 5) }
    blockers.each { |blocker| link(blocker, create_issue) }

    perform_migration

    expect(blockers.map { |blocker| blocker.reload.blocking_issues_count }).to match_array([1, 1, 1])
  end

  it 'does not write a count that is already right', :aggregate_failures do
    blocker = create_issue(blocking_issues_count: 1)
    link(blocker, create_issue)

    expect { perform_migration }.not_to change { row_version(blocker) }
    expect(blocker.reload.blocking_issues_count).to eq(1)
  end

  it 'raises a count of 0 left too low to the open issues blocked' do
    blocker = create_issue
    link(blocker, create_issue)
    link(blocker, create_issue(state_id: closed_state_id))

    expect { perform_migration }.to change { blocker.reload.blocking_issues_count }.from(0).to(1)
  end

  it 'recounts closed blockers too' do
    left_too_high = create_issue(state_id: closed_state_id, blocking_issues_count: 1)
    link(left_too_high, create_issue(state_id: closed_state_id))
    left_too_low = create_issue(state_id: closed_state_id)
    link(left_too_low, create_issue)

    expect { perform_migration }
      .to change { left_too_high.reload.blocking_issues_count }.from(1).to(0)
      .and change { left_too_low.reload.blocking_issues_count }.from(0).to(1)
  end

  it 'leaves a right count of 0 alone', :aggregate_failures do
    unlinked = create_issue
    blocker_of_closed = create_issue
    link(blocker_of_closed, create_issue(state_id: closed_state_id))

    expect { perform_migration }.not_to change { [row_version(unlinked), row_version(blocker_of_closed)] }
    expect([unlinked, blocker_of_closed].map { |issue| issue.reload.blocking_issues_count }).to match_array([0, 0])
  end

  def create_issue(state_id: opened_state_id, blocking_issues_count: 0)
    issues.create!(
      title: 'issue', project_id: project.id, namespace_id: project_namespace.id, work_item_type_id: 1,
      state_id: state_id, blocking_issues_count: blocking_issues_count
    )
  end

  def link(source, target, link_type: blocks_link_type)
    issue_links.create!(source_id: source.id, target_id: target.id, link_type: link_type)
  end

  # Every UPDATE writes a new row version at a new ctid, even one that changes no value.
  def row_version(issue)
    issues.where(id: issue.id).pick(Arel.sql('ctid::text'))
  end

  def perform_migration
    described_class.new(
      start_cursor: [issues.minimum(:id)],
      end_cursor: [issues.maximum(:id)],
      batch_table: :issues,
      batch_column: :id,
      sub_batch_size: 2,
      pause_ms: 0,
      connection: ApplicationRecord.connection
    ).perform
  end
end
