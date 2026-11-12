# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::ProjectSettingParams, feature_category: :security_policy_management do
  it 'writes exactly the settings the evaluation context reads' do
    stub_licensed_features(secret_push_protection: true)
    project = create(:project)
    # A NULL squash_option is missing from the context, so set one.
    project.project_setting.update!(squash_option: 'never')

    writable = described_class::TARGETS.keys +
      Govern::PolicyEngine::ApprovalSettings.settings +
      [Govern::PolicyEngine::ProjectSettingWriter::SECURITY_SETTING]

    expect(Govern::PolicyEngine::ProjectSettingsContext.settings_for(project).keys).to match_array(writable)
  end

  describe '.for' do
    it 'turns a visibility name into the level the column stores' do
      expect(described_class.for('visibility', 'internal'))
        .to eq({ visibility_level: Gitlab::VisibilityLevel::INTERNAL })
    end

    it 'passes a plain project column straight through' do
      expect(described_class.for('request_access_enabled', false)).to eq({ request_access_enabled: false })
    end

    it 'renames an approval setting to its column' do
      expect(described_class.for('allow_author_approval', false))
        .to eq({ merge_requests_author_approval: false })
    end

    it 'inverts an approval setting whose column disables what the catalog allows', :aggregate_failures do
      expect(described_class.for('allow_committer_approval', false))
        .to eq({ merge_requests_disable_committers_approval: true })
      expect(described_class.for('allow_overrides_to_approver_list_per_merge_request', false))
        .to eq({ disable_overriding_approvers_per_merge_request: true })
      expect(described_class.for('retain_approvals_on_push', true))
        .to eq({ reset_approvals_on_push: false })
    end

    it 'nests a project setting' do
      expect(described_class.for('squash_option', 'never'))
        .to eq({ project_setting_attributes: { squash_option: 'never' } })
    end

    it 'nests a CI/CD setting' do
      expect(described_class.for('keep_latest_artifact', true))
        .to eq({ ci_cd_settings_attributes: { keep_latest_artifact: true } })
    end

    it 'writes the pipeline variables role through the guarded top-level param' do
      expect(described_class.for('pipeline_variables_minimum_override_role', 'maintainer'))
        .to eq({ ci_pipeline_variables_minimum_override_role: 'maintainer' })
    end

    it 'turns a feature access level name into the number the column stores' do
      expect(described_class.for('builds_access_level', 'enabled'))
        .to eq({ project_feature_attributes: { builds_access_level: ProjectFeature::ENABLED } })
    end

    it 'is nil for a setting with no write mapping' do
      expect(described_class.for('no_such_setting', true)).to be_nil
    end

    it 'is nil for a visibility value that is not a known name', :aggregate_failures do
      expect(described_class.for('visibility', 'publik')).to be_nil
      expect(described_class.for('visibility', '10')).to be_nil
      expect(described_class.for('visibility', 10)).to be_nil
      expect(described_class.for('visibility', true)).to be_nil
    end

    it 'is nil for a feature access level name it does not know' do
      expect(described_class.for('builds_access_level', 'enabledd')).to be_nil
    end

    it 'is nil for a squash option it does not know, instead of raising at enum assignment' do
      expect(described_class.for('squash_option', 'sometimes')).to be_nil
    end

    it 'is nil for a pipeline variables role it does not know, instead of raising at enum assignment' do
      expect(described_class.for('pipeline_variables_minimum_override_role', 'admin')).to be_nil
    end

    it 'is nil for a boolean column when the value is not a real boolean', :aggregate_failures do
      expect(described_class.for('request_access_enabled', 'no')).to be_nil
      expect(described_class.for('keep_latest_artifact', 'true')).to be_nil
      expect(described_class.for('remove_source_branch_after_merge', nil)).to be_nil
    end

    it 'is nil for a target whose cast the converter does not know' do
      target = described_class::Target.new(column: :some_column, cast: :unknown_cast)

      expect(target.params_for('anything')).to be_nil
    end

    it 'is nil for an approval setting when the value is not a real boolean', :aggregate_failures do
      expect(described_class.for('allow_author_approval', nil)).to be_nil
      expect(described_class.for('allow_author_approval', 'no')).to be_nil
      expect(described_class.for('allow_committer_approval', 'disabled')).to be_nil
    end
  end
end
