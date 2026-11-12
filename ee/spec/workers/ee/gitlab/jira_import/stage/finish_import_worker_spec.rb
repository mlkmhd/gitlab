# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::JiraImport::Stage::FinishImportWorker, feature_category: :importers do
  let_it_be(:project) { create(:project) }
  let_it_be(:import_label) { create(:label, project: project, title: 'jira-import') }
  let_it_be_with_reload(:jira_import) { create(:jira_import_state, :scheduled, project: project) }

  before do
    allow(Gitlab::JiraImport).to receive_messages(get_import_label_id: import_label.id, issue_failures: 0)
    jira_import.start!
  end

  it 'writes the missing status rows once the import has finished' do
    expect(::WorkItems::Statuses::BackfillProjectRowsWorker).to receive(:perform_async).with(project.id)

    described_class.new.perform(project.id)

    expect(project.reload.jira_import_status).to eq('finished')
  end
end
