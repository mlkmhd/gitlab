# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::ProposedProjectSettings, feature_category: :security_policy_management do
  def proposed(params)
    described_class.from_params(params)
  end

  it 'returns an empty map for params that touch no governed setting' do
    expect(proposed(name: 'renamed', description: 'x')).to eq({})
  end

  it 'accepts ActionController::Parameters, including nested attributes' do
    params = ActionController::Parameters.new(
      only_allow_merge_if_pipeline_succeeds: '0',
      project_setting_attributes: { squash_option: 'never' }
    )

    expect(proposed(params)).to eq(
      'only_allow_merge_if_pipeline_succeeds' => false, 'squash_option' => 'never'
    )
  end

  it 'casts form booleans on project columns', :aggregate_failures do
    expect(proposed(request_access_enabled: '1')).to eq('request_access_enabled' => true)
    expect(proposed(only_allow_merge_if_pipeline_succeeds: '0'))
      .to eq('only_allow_merge_if_pipeline_succeeds' => false)
  end

  it 'maps visibility_level integers and strings to the visibility string', :aggregate_failures do
    expect(proposed(visibility_level: 20)).to eq('visibility' => 'public')
    expect(proposed(visibility_level: '0')).to eq('visibility' => 'private')
    expect(proposed(visibility: 'internal')).to eq('visibility' => 'internal')
  end

  it 'translates the approval columns into catalog terms, inverting where the column disables', :aggregate_failures do
    expect(proposed(merge_requests_author_approval: '1')).to eq('allow_author_approval' => true)
    expect(proposed(merge_requests_disable_committers_approval: '1')).to eq('allow_committer_approval' => false)
    expect(proposed(disable_overriding_approvers_per_merge_request: '0'))
      .to eq('allow_overrides_to_approver_list_per_merge_request' => true)
    expect(proposed(reset_approvals_on_push: '1')).to eq('retain_approvals_on_push' => false)
  end

  it 'reads nested project_setting attributes', :aggregate_failures do
    expect(proposed(project_setting_attributes: { squash_option: 'always' })).to eq('squash_option' => 'always')
    expect(proposed(project_setting_attributes: { squash_option: '3' }))
      .to eq('squash_option' => ProjectSetting.squash_options.key(3))
  end

  it 'reads nested ci_cd attributes' do
    attrs = { keep_latest_artifact: '0', pipeline_variables_minimum_override_role: 'owner' }

    expect(proposed(ci_cd_settings_attributes: attrs))
      .to eq('keep_latest_artifact' => false, 'pipeline_variables_minimum_override_role' => 'owner')
  end

  it 'maps a pipeline variables override role integer to its name' do
    expect(proposed(ci_cd_settings_attributes: { pipeline_variables_minimum_override_role: '3' }))
      .to eq('pipeline_variables_minimum_override_role' => 'maintainer')
  end

  it 'maps feature access level integers to their string names', :aggregate_failures do
    expect(proposed(project_feature_attributes: { merge_requests_access_level: '10' }))
      .to eq('merge_requests_access_level' => 'private')
    expect(proposed(project_feature_attributes: { builds_access_level: 20 }))
      .to eq('builds_access_level' => 'enabled')
  end

  it 'reads the top-level params Project delegates to its associations', :aggregate_failures do
    expect(proposed(squash_option: 'always')).to eq('squash_option' => 'always')
    expect(proposed(keep_latest_artifact: false)).to eq('keep_latest_artifact' => false)
    expect(proposed(ci_allow_fork_pipelines_to_run_in_parent_project: '1'))
      .to eq('allow_fork_pipelines_to_run_in_parent_project' => true)
    expect(proposed(ci_pipeline_variables_minimum_override_role: 'developer'))
      .to eq('pipeline_variables_minimum_override_role' => 'developer')
    expect(proposed(forking_access_level: 'private')).to eq('forking_access_level' => 'private')
  end

  it 'maps the boolean feature flags to enabled or disabled', :aggregate_failures do
    expect(proposed(builds_enabled: false)).to eq('builds_access_level' => 'disabled')
    expect(proposed(merge_requests_enabled: '1')).to eq('merge_requests_access_level' => 'enabled')
  end

  it 'collects several touched settings at once' do
    expect(proposed(request_access_enabled: true, visibility_level: 0,
      project_feature_attributes: { forking_access_level: 20 }).keys)
      .to contain_exactly('request_access_enabled', 'visibility', 'forking_access_level')
  end
end
