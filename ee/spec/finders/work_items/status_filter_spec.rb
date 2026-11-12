# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::StatusFilter, feature_category: :team_planning do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:current_user) { create(:user, guest_of: group) }

  let_it_be(:issue_type) { build(:work_item_system_defined_type, :issue) }
  let_it_be(:task_type) { build(:work_item_system_defined_type, :task) }

  let_it_be(:lifecycle) do
    create(:work_item_custom_lifecycle, namespace: group).tap do |lifecycle|
      [issue_type, task_type].each do |type|
        # Skip validations to avoid the license check, which can't be stubbed in let_it_be.
        build(:work_item_type_custom_lifecycle, namespace: group, work_item_type: type, lifecycle: lifecycle)
          .save!(validate: false)
      end
    end
  end

  let_it_be(:target_status) { create_status(:without_conversion_mapping) }
  let_it_be(:converted_status) { create_status(:in_progress) }
  let_it_be(:other_status) { create_status(:without_conversion_mapping) }

  before do
    stub_licensed_features(work_item_status: true)
  end

  subject(:filtered_ids) do
    described_class.new(
      params: { status: { name: status_name } },
      parent: group,
      current_user: current_user
    ).filter(WorkItem.where(namespace_id: project.project_namespace_id)).pluck(:id)
  end

  context 'when a converted status maps into the filtered status and away at another type' do
    let(:status_name) { target_status.name }

    let_it_be(:issue_in_target_status) { create_work_item(:issue, target_status) }
    let_it_be(:task_mapped_to_target_status) { create_work_item(:task, converted_status) }

    before_all do
      create_mapping(task_type, converted_status, target_status)
      create_mapping(issue_type, converted_status, other_status)
    end

    it 'returns every item that displays the filtered status' do
      expect(filtered_ids).to contain_exactly(issue_in_target_status.id, task_mapped_to_target_status.id)
    end
  end

  context 'when an item maps away to a status outside the filter' do
    let(:status_name) { converted_status.name }

    let_it_be(:issue_mapped_away) { create_work_item(:issue, converted_status) }
    let_it_be(:task_keeps_status) { create_work_item(:task, converted_status) }

    before_all do
      create_mapping(issue_type, converted_status, other_status)
    end

    it 'excludes the mapped-away item and keeps the one that still displays the status' do
      expect(filtered_ids).to contain_exactly(task_keeps_status.id)
    end
  end

  context 'when the mapped-away mapping only applies within a time window' do
    let(:status_name) { target_status.name }

    let_it_be(:item_before_window) { create_work_item(:issue, target_status, updated_at: 5.days.ago) }
    let_it_be(:item_in_window) { create_work_item(:issue, target_status, updated_at: 3.days.ago) }
    let_it_be(:item_after_window) { create_work_item(:issue, target_status, updated_at: 1.day.ago) }

    before_all do
      create_mapping(issue_type, target_status, other_status, valid_from: 4.days.ago, valid_until: 2.days.ago)
    end

    it 'excludes only items whose status falls inside the mapping window' do
      expect(filtered_ids).to contain_exactly(item_before_window.id, item_after_window.id)
    end
  end

  context 'when the mapped-away mapping only has a start (no end)' do
    let(:status_name) { target_status.name }

    let_it_be(:item_before_start) { create_work_item(:issue, target_status, updated_at: 5.days.ago) }
    let_it_be(:item_after_start) { create_work_item(:issue, target_status, updated_at: 1.day.ago) }

    before_all do
      create_mapping(issue_type, target_status, other_status, valid_from: 3.days.ago)
    end

    it 'excludes items whose status is at or after the start' do
      expect(filtered_ids).to contain_exactly(item_before_start.id)
    end
  end

  context 'when the mapped-away mapping only has an end (no start)' do
    let(:status_name) { target_status.name }

    let_it_be(:item_before_end) { create_work_item(:issue, target_status, updated_at: 3.days.ago) }
    let_it_be(:item_after_end) { create_work_item(:issue, target_status, updated_at: 1.day.ago) }

    before_all do
      create_mapping(issue_type, target_status, other_status, valid_until: 2.days.ago)
    end

    it 'excludes items whose status is at or before the end' do
      expect(filtered_ids).to contain_exactly(item_after_end.id)
    end
  end

  context 'when the namespace uses the system-defined lifecycle' do
    let_it_be(:system_defined_group) { create(:group) }
    let_it_be(:system_defined_project) { create(:project, group: system_defined_group) }

    # Factories bypass the status callback, so neither item gets a current_status
    # record and both display the default open status through the fallback.
    let_it_be(:open_issue) { create(:work_item, :issue, project: system_defined_project) }
    let_it_be(:open_epic) { create(:work_item, :epic, namespace: system_defined_group) }

    subject(:filtered_ids) do
      described_class.new(
        params: { status: { name: 'To do' }, issue_types: %w[issue epic] },
        parent: system_defined_group,
        current_user: current_user
      ).filter(
        WorkItem.where(namespace_id: [system_defined_project.project_namespace_id, system_defined_group.id])
      ).pluck(:id)
    end

    it 'returns the issue and the epic that fall back to the default status' do
      expect(filtered_ids).to contain_exactly(open_issue.id, open_epic.id)
    end

    context 'when the epic status flag is disabled' do
      before do
        stub_feature_flags(work_item_status_for_epics: false)
      end

      it 'returns only the issue' do
        expect(filtered_ids).to contain_exactly(open_issue.id)
      end
    end
  end

  context 'when the custom lifecycle default open status differs from the converted to-do status' do
    let_it_be(:epic_type) { build(:work_item_system_defined_type, :epic) }
    let_it_be(:new_status) { create(:work_item_custom_status, :triage, name: 'New', namespace: group) }
    let_it_be(:converted_to_do_status) { create(:work_item_custom_status, :to_do, name: 'Start', namespace: group) }

    # Factories bypass the status callback, so neither item gets a current_status
    # record and both display the lifecycle default (New) through the fallback.
    let_it_be(:epic_without_record) { create(:work_item, :epic, namespace: group) }
    let_it_be(:issue_without_record) { create(:work_item, :issue, project: project) }

    let(:issue_types) { %w[issue epic] }

    before do
      stub_feature_flags(work_item_status_single_column_filter: false)
    end

    before_all do
      create(:work_item_custom_lifecycle_status, lifecycle: lifecycle, status: converted_to_do_status)
      build(:work_item_type_custom_lifecycle, namespace: group, work_item_type: epic_type, lifecycle: lifecycle)
        .save!(validate: false)
      # The shared lifecycle is frozen by let_it_be, so update a fresh instance.
      ::WorkItems::Statuses::Custom::Lifecycle.find(lifecycle.id).update!(default_open_status: new_status)
    end

    subject(:filtered_ids) do
      described_class.new(
        params: { status: { name: status_name }, issue_types: issue_types },
        parent: group,
        current_user: current_user
      ).filter(
        WorkItem.where(namespace_id: [project.project_namespace_id, group.id])
      ).pluck(:id)
    end

    context 'with a converted (renamed) issue type' do
      let_it_be(:converted_type) do
        create(:work_item_custom_type, :converted_from_issue, name: 'Feature', namespace: group)
      end

      before do
        stub_saas_features(namespace_scoped_work_item_types: true)
      end

      def filtered_by_new(params)
        described_class.new(
          params: { status: { name: new_status.name } }.merge(params), parent: group, current_user: current_user
        ).filter(WorkItem.where(namespace_id: project.project_namespace_id)).pluck(:id)
      end

      it 'matches the item without a status record with work_item_type_ids' do
        expect(filtered_by_new(work_item_type_ids: [issue_type.id])).to contain_exactly(issue_without_record.id)
      end

      it 'matches the item without a status record without a type filter' do
        expect(filtered_by_new({})).to contain_exactly(issue_without_record.id)
      end
    end

    context 'when filtering by the default open status' do
      let(:status_name) { new_status.name }

      it 'returns the items without a status record' do
        expect(filtered_ids).to contain_exactly(epic_without_record.id, issue_without_record.id)
      end

      context 'without a type filter' do
        let(:issue_types) { nil }

        it 'returns the items without a status record' do
          expect(filtered_ids).to contain_exactly(epic_without_record.id, issue_without_record.id)
        end
      end

      context 'with work_item_type_ids' do
        subject(:filtered_ids) do
          described_class.new(
            params: { status: { name: status_name }, work_item_type_ids: [epic_type.id] },
            parent: group,
            current_user: current_user
          ).filter(
            WorkItem.where(namespace_id: [project.project_namespace_id, group.id])
          ).pluck(:id)
        end

        it 'returns only the items of the requested types' do
          expect(filtered_ids).to contain_exactly(epic_without_record.id)
        end
      end
    end

    context 'when filtering by the converted to-do status' do
      let(:status_name) { converted_to_do_status.name }

      it 'does not return the items without a status record' do
        expect(filtered_ids).to be_empty
      end

      context 'without a type filter' do
        let(:issue_types) { nil }

        it 'does not return the items without a status record' do
          expect(filtered_ids).to be_empty
        end
      end
    end
  end

  def create_status(trait)
    create(:work_item_custom_status, trait, namespace: group).tap do |status|
      create(:work_item_custom_lifecycle_status, lifecycle: lifecycle, status: status)
    end
  end

  def create_work_item(type, custom_status, updated_at: 1.hour.ago)
    create(:work_item, type, project: project).tap do |work_item|
      create(:work_item_current_status, :custom, work_item: work_item, custom_status: custom_status,
        updated_at: updated_at)
    end
  end

  def create_mapping(work_item_type, old_status, new_status, valid_from: nil, valid_until: nil)
    create(:work_item_custom_status_mapping,
      namespace: group,
      work_item_type: work_item_type,
      old_status: old_status,
      new_status: new_status,
      valid_from: valid_from,
      valid_until: valid_until
    )
  end
end
