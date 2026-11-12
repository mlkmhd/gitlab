# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BulkImports::Projects::Pipelines::CiCdSettingsPipeline, :clean_gitlab_redis_shared_state,
  feature_category: :importers do
  let_it_be(:project, freeze: false) { create(:project) }
  let_it_be(:other_project) { create(:project) }
  let_it_be(:entity, freeze: false) { create(:bulk_import_entity, :project_entity, project: project) }
  let_it_be(:tracker, freeze: false) { create(:bulk_import_tracker, entity: entity) }
  let_it_be(:context, freeze: false) { BulkImports::Pipeline::Context.new(tracker) }

  let(:ci_cd_settings) { project.reload.ci_cd_settings }

  subject(:pipeline) { described_class.new(context) }

  before do
    allow_next_instance_of(BulkImports::Common::Extractors::NdjsonExtractor) do |extractor|
      allow(extractor).to receive(:extract)
        .and_return(BulkImports::Pipeline::ExtractedData.new(data: [[settings, 0]]))
    end

    allow(pipeline).to receive(:set_source_objects_counter)
  end

  context 'when the source exports all current CI/CD settings' do
    let(:settings) do
      Gitlab::Json::SafeParser.parse(
        File.read('spec/fixtures/lib/gitlab/import_export/complex/tree/project/ci_cd_settings.ndjson')
      ).merge('id' => non_existing_record_id, 'project_id' => other_project.id)
    end

    let!(:existing_settings_id) { project.ci_cd_settings.id }

    before do
      pipeline.run
    end

    it_behaves_like 'restores all exported CI/CD settings'

    it 'updates the existing record and ignores the exported id and project_id', :aggregate_failures do
      expect(ci_cd_settings.id).to eq(existing_settings_id)
      expect(other_project.reload.ci_cd_settings.default_git_depth).not_to eq(ci_cd_settings.default_git_depth)
    end
  end

  context 'when the source exports fewer or unknown CI/CD settings' do
    let(:settings) { { 'default_git_depth' => 7, 'setting_unknown_to_destination' => true } }

    it 'restores the exported settings and keeps the defaults of the others', :aggregate_failures do
      defaults = project.reload.ci_cd_settings.attributes.except('default_git_depth', 'updated_at')

      pipeline.run

      expect(entity.failures).to be_empty
      expect(ci_cd_settings.default_git_depth).to eq(7)
      expect(ci_cd_settings.attributes.except('default_git_depth', 'updated_at')).to eq(defaults)
    end
  end
end
