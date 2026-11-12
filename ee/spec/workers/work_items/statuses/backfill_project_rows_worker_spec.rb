# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Statuses::BackfillProjectRowsWorker, feature_category: :team_planning do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:other_project) { create(:project, group: group) }
  let_it_be(:lifecycle) do
    create(:work_item_custom_lifecycle, namespace: group).tap do |lifecycle|
      # Skips the license check, which cannot be stubbed in let_it_be.
      build(:work_item_type_custom_lifecycle, namespace: group, lifecycle: lifecycle,
        work_item_type: build(:work_item_system_defined_type, :issue)).save!(validate: false)
    end
  end

  let_it_be(:open_issue) { create(:work_item, project: project) }
  let_it_be(:closed_issue) { create(:work_item, :closed, project: project) }
  let_it_be(:other_project_issue) { create(:work_item, project: other_project) }

  let(:limiter) { instance_double(Gitlab::Metrics::RuntimeLimiter, over_time?: false) }

  before do
    allow(Gitlab::Metrics::RuntimeLimiter).to receive(:new).and_return(limiter)
  end

  def row_for(item)
    WorkItems::Statuses::CurrentStatus.find_by(work_item_id: item.id)
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [project.id] }

    it 'inserts the lifecycle default for the work items of the project only' do
      perform_idempotent_work

      expect(row_for(open_issue).custom_status_id).to eq(lifecycle.default_open_status_id)
      expect(row_for(closed_issue).custom_status_id).to eq(lifecycle.default_closed_status_id)
      expect(row_for(other_project_issue)).to be_nil
    end
  end

  context 'when the limiter is over time' do
    let(:limiter) { instance_double(Gitlab::Metrics::RuntimeLimiter, over_time?: true) }

    it 'continues from where it stopped' do
      stub_const("WorkItems::Statuses::BackfillConvertedStatusIdsService::BATCH_SIZE", 1)

      expect(described_class).to receive(:perform_in).with(described_class::RETRY_DELAY, project.id, open_issue.iid)

      described_class.new.perform(project.id)
    end
  end

  context 'when resuming a previous run' do
    it 'only handles the work items after the given iid' do
      described_class.new.perform(project.id, open_issue.iid)

      expect(row_for(open_issue)).to be_nil
      expect(row_for(closed_issue).custom_status_id).to eq(lifecycle.default_closed_status_id)
    end
  end

  context 'when the group has no custom lifecycle' do
    let_it_be(:unconverted_project) { create(:project) }

    it 'does nothing' do
      expect(WorkItems::Statuses::BackfillConvertedStatusIdsService).not_to receive(:new)

      described_class.new.perform(unconverted_project.id)
    end
  end

  it 'does nothing for an unknown project' do
    expect(WorkItems::Statuses::BackfillConvertedStatusIdsService).not_to receive(:new)

    described_class.new.perform(non_existing_record_id)
  end
end
