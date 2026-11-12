# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::UpdateBlockingIssuesCountWorker, feature_category: :portfolio_management do
  let_it_be(:project) { create(:project) }
  let_it_be_with_reload(:blocking_issue) { create(:issue, project: project) }
  let_it_be_with_reload(:other_blocking_issue) { create(:issue, project: project) }
  let_it_be(:blocked_issue) { create(:issue, project: project) }

  before_all do
    create(:issue_link, source: blocking_issue, target: blocked_issue, link_type: IssueLink::TYPE_BLOCKS)
  end

  it_behaves_like 'worker with data consistency', described_class, data_consistency: :delayed

  it 'defers on the database health signal of the issues tables' do
    expect(described_class.database_health_check_attrs).to include(
      gitlab_schema: :gitlab_main_org, tables: [:issues, :issue_links], delay_by: 1.minute
    )
  end

  describe '#perform' do
    before do
      blocking_issue.update_column(:blocking_issues_count, 5)
      other_blocking_issue.update_column(:blocking_issues_count, 5)
    end

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [[blocking_issue.id, other_blocking_issue.id, non_existing_record_id]] }

      it 'recounts the blocking issues count of every given issue' do
        expect { perform_idempotent_work }
          .to change { blocking_issue.reload.blocking_issues_count }.from(5).to(1)
          .and change { other_blocking_issue.reload.blocking_issues_count }.from(5).to(0)
      end
    end
  end
end
