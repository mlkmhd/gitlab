# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::ImportExport::RelationImportWorker, feature_category: :importers do
  let_it_be(:tracker) { create(:relation_import_tracker, status: 'created') }
  let_it_be(:user) { create(:user) }

  before do
    create(
      :import_export_upload,
      import_file: fixture_file_upload('spec/features/projects/import_export/test_project_export.tar.gz'),
      project: tracker.project,
      user: user
    )
  end

  it 'writes the missing status rows once the relation is imported' do
    allow_next_instance_of(Gitlab::ImportExport::Project::RelationTreeRestorer) do |restorer|
      allow(restorer).to receive(:restore_single_relation)
    end

    expect(::WorkItems::Statuses::BackfillProjectRowsWorker).to receive(:perform_async).with(tracker.project.id)

    described_class.new.perform(tracker.id, user.id)
  end

  context 'when the importer maps an enterprise user', :saas do
    let_it_be(:root_group) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: root_group) }
    let_it_be(:owner) { create(:user, owner_of: root_group) }
    let_it_be(:enterprise_user) { create(:enterprise_user, enterprise_group: root_group) }
    let_it_be(:enterprise_tracker) do
      create(:relation_import_tracker, project: create(:project, group: subgroup), relation: :issues)
    end

    subject(:perform) { described_class.new.perform(enterprise_tracker.id, owner.id) }

    before do
      stub_licensed_features(domain_verification: true)

      create(
        :import_export_upload,
        import_file: fixture_file_upload('spec/features/projects/import_export/test_project_export.tar.gz'),
        project: enterprise_tracker.project,
        user: owner
      )

      # The fixture's only member has no public email.
      allow_next_instance_of(Gitlab::ImportExport::Json::NdjsonReader) do |reader|
        allow(reader).to receive(:consume_relation).and_call_original
        allow(reader).to receive(:consume_relation)
          .with('project', 'project_members', mark_as_consumed: false)
          .and_return([[{ 'access_level' => 30, 'user' => { 'id' => 1, 'public_email' => enterprise_user.email } },
            0]].each)
      end
    end

    it 'imports issues authored by the enterprise user' do
      perform

      expect(enterprise_tracker.project.issues.first.author).to eq(enterprise_user)
    end
  end
end
