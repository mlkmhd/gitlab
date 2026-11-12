# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying a project\'s security scan profiles', feature_category: :security_testing_configuration do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, developer_of: project) }

  let(:trigger_settings_selection) do
    <<~SELECTION
      name
      triggerSettings {
        triggerType
        configuration {
          __typename
          ... on AutoRemediationConfiguration { cooldown severityLevel upgradePolicy }
        }
      }
    SELECTION
  end

  let(:query) do
    graphql_query_for(:project, { full_path: project.full_path },
      query_graphql_field(:security_scan_profiles, {}, trigger_settings_selection))
  end

  let(:profiles_data) { graphql_data_at(:project, :security_scan_profiles) }

  def attach_profile_with_trigger(name)
    profile = create(:security_scan_profile, :dependency_scanning_post_processing, namespace: group, name: name)
    create(:security_scan_profile_project, scan_profile: profile, project: project)
    create(:security_scan_profile_trigger, scan_profile: profile, trigger_type: :sbom_ingested,
      configuration_values: { 'auto_remediation' => { 'severity_level' => 'critical' } })
    profile
  end

  before do
    stub_licensed_features(security_scan_profiles: true)
    attach_profile_with_trigger('Profile 1')
  end

  it 'returns the effective trigger configuration for each attached profile' do
    post_graphql(query, current_user: user)

    config = profiles_data.dig(0, 'triggerSettings', 0, 'configuration')

    expect(config['__typename']).to eq('AutoRemediationConfiguration')
    expect(config).to include(
      'severityLevel' => 'CRITICAL', # persisted override
      'cooldown' => 7,               # merged default
      'upgradePolicy' => 'MINOR'     # merged default
    )
  end

  it 'computes the effective configuration scoped to the project so project-specific overrides apply' do
    allow(Security::ScanProfiles::Configuration).to receive(:effective_for).and_call_original

    post_graphql(query, current_user: user)

    expect(graphql_errors).to be_nil
    expect(Security::ScanProfiles::Configuration)
      .to have_received(:effective_for).with(anything, anything, project: an_instance_of(Project)).at_least(:once)
  end

  it 'avoids N+1 queries as the number of attached profiles grows' do
    post_graphql(query, current_user: user) # warm up before recording the control
    control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: user) }
    expect(profiles_data).to be_present

    attach_profile_with_trigger('Profile 2')
    attach_profile_with_trigger('Profile 3')

    expect { post_graphql(query, current_user: user) }.not_to exceed_query_limit(control)
  end

  context 'with an attached Business Logic profile' do
    include_context 'with bl_security enabled for the instance'

    before do
      profile = create(:security_scan_profile, scan_type: :business_logic, namespace: group, name: 'BL profile')
      create(:security_scan_profile_project, scan_profile: profile, project: project)
    end

    it 'returns it when the bl_security_analyzer flag is enabled for the root group' do
      stub_feature_flags(bl_security_analyzer: group)
      stub_application_setting(instance_level_ai_beta_features_enabled: true)

      post_graphql(query, current_user: user)

      expect(profiles_data.pluck('name')).to contain_exactly('Profile 1', 'BL profile')
    end

    context 'when the flow is beta' do
      before do
        stub_feature_flags(bl_security_analyzer: group)
        allow(Ai::Catalog::FoundationalFlow.bl_security_experimental).to receive(:beta?).and_return(true)
      end

      it 'hides it with Experiment and beta features off' do
        stub_application_setting(instance_level_ai_beta_features_enabled: false)

        post_graphql(query, current_user: user)

        expect(profiles_data.pluck('name')).to contain_exactly('Profile 1')
      end

      it 'returns it with Experiment and beta features on' do
        stub_application_setting(instance_level_ai_beta_features_enabled: true)

        post_graphql(query, current_user: user)

        expect(profiles_data.pluck('name')).to contain_exactly('Profile 1', 'BL profile')
      end
    end

    it 'hides it when the bl_security_analyzer flag is disabled' do
      stub_feature_flags(bl_security_analyzer: false)

      post_graphql(query, current_user: user)

      expect(profiles_data.pluck('name')).to contain_exactly('Profile 1')
    end

    context 'on GitLab Dedicated with the bl_security_analyzer flag off', :dedicated do
      before do
        stub_feature_flags(bl_security_analyzer: false)
        stub_application_setting(instance_level_ai_beta_features_enabled: true)
      end

      it 'returns it when GitLab enabled the flow for the instance' do
        allow(Ai::Catalog::FoundationalFlows::EnabledFlowsClient).to receive(:enabled?)
          .with('bl_security').and_return(true)

        post_graphql(query, current_user: user)

        expect(profiles_data.pluck('name')).to contain_exactly('Profile 1', 'BL profile')
      end

      it 'hides it when GitLab has not enabled the flow for the instance' do
        allow(Ai::Catalog::FoundationalFlows::EnabledFlowsClient).to receive(:enabled?)
          .with('bl_security').and_return(false)

        post_graphql(query, current_user: user)

        expect(profiles_data.pluck('name')).to contain_exactly('Profile 1')
      end
    end
  end

  context 'with an attached SkillGuard profile' do
    before do
      profile = create(:security_scan_profile, scan_type: :skillguard, namespace: group, name: 'SkillGuard profile')
      create(:security_scan_profile_project, scan_profile: profile, project: project)
    end

    it 'returns it when the skillguard_analyzer flag is enabled for the root group' do
      stub_feature_flags(skillguard_analyzer: group)

      post_graphql(query, current_user: user)

      expect(profiles_data.pluck('name')).to contain_exactly('Profile 1', 'SkillGuard profile')
    end

    it 'hides it when the skillguard_analyzer flag is disabled' do
      stub_feature_flags(skillguard_analyzer: false)

      post_graphql(query, current_user: user)

      expect(profiles_data.pluck('name')).to contain_exactly('Profile 1')
    end
  end

  describe 'across a list of projects', :request_store, :use_sql_query_cache do
    let_it_be(:list_user) { create(:user, developer_of: group) }

    let(:projects_query) do
      graphql_query_for(:group, { full_path: group.full_path },
        'projects(includeSubgroups: true) { nodes { securityScanProfiles { name } } }')
    end

    def namespace_settings_query_count
      recorder = ActiveRecord::QueryRecorder.new(skip_cached: false) do
        post_graphql(projects_query, current_user: list_user)
      end
      recorder.log.count { |sql| sql.include?('"namespace_settings"') }
    end

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_feature_flags(bl_security_analyzer: group)
      allow(Ai::Catalog::FoundationalFlow.bl_security_experimental).to receive(:beta?).and_return(true)
    end

    it 'reads the root group settings once, however many projects are listed' do
      post_graphql(projects_query, current_user: list_user) # warm up before recording the control
      control = namespace_settings_query_count

      create(:project, group: group)
      # A subgroup project loads its own root group object, so only the cache can share the result.
      create(:project, group: create(:group, parent: group))

      expect(namespace_settings_query_count).to eq(control)
      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:group, :projects, :nodes, :security_scan_profiles, :name).flatten).to include('Profile 1')
      expect(graphql_data_at(:group, :projects, :nodes).size).to eq(3)
    end
  end
end
