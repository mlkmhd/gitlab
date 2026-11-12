# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying security scan profile variables', feature_category: :security_testing_configuration do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }

  let(:scan_type) { :SECRET_DETECTION }

  let(:query) do
    graphql_query_for(
      :security_scan_profile_variables,
      { scan_type: scan_type },
      'key envVar label description valueType placeholder min max options { value text }'
    )
  end

  let(:variables) { graphql_data_at(:security_scan_profile_variables) }

  it 'returns the secret detection variables' do
    post_graphql(query, current_user: user)

    expect(variables.pluck('key')).to eq(%w[
      secureAnalyzersPrefix imageSuffix historicScan logOptions excludedPaths rulesetGitReference
    ])
    expect(variables).to include(
      'key' => 'excludedPaths',
      'envVar' => 'SECRET_DETECTION_EXCLUDED_PATHS',
      'label' => 'Paths to exclude',
      'description' => 'Paths left out of the scan.',
      'valueType' => 'STRING_LIST',
      'placeholder' => 'spec/**',
      'min' => nil,
      'max' => nil,
      'options' => nil
    )
  end

  it 'returns the options of an enum variable' do
    post_graphql(query, current_user: user)

    expect(variables).to include(
      a_hash_including(
        'key' => 'imageSuffix',
        'valueType' => 'ENUM',
        'options' => [{ 'value' => '', 'text' => 'Default' }, { 'value' => '-fips', 'text' => 'FIPS' }]
      )
    )
  end

  context 'when a placeholder is a literal example containing a pipe' do
    before do
      stub_const('::Security::ScanProfiles::Configuration::ScanProfileVariables::MAPPINGS', {
        secret_detection: {
          log_options: { env: 'SECRET_DETECTION_LOG_OPTIONS', type: :string, label: 'Label',
                         description: 'Description', placeholder: 'main|develop' }
        }
      })
    end

    it 'returns the placeholder unchanged' do
      post_graphql(query, current_user: user)

      expect(variables).to contain_exactly(a_hash_including('key' => 'logOptions', 'placeholder' => 'main|develop'))
    end
  end

  context 'when the scan type is SAST' do
    let(:scan_type) { :SAST }

    it 'returns the SAST variables' do
      post_graphql(query, current_user: user)

      expect(variables.pluck('envVar')).to include('SAST_EXCLUDED_ANALYZERS', 'GITLAB_ADV_SAST_INCR_SCAN')
    end
  end

  context 'when the scan type is DEPENDENCY_SCANNING' do
    let(:scan_type) { :DEPENDENCY_SCANNING }

    it 'returns the dependency scanning variables' do
      post_graphql(query, current_user: user)

      expect(variables).to include(
        a_hash_including('key' => 'pipExtraIndexUrl', 'envVar' => 'PIP_EXTRA_INDEX_URL', 'valueType' => 'STRING_LIST'),
        a_hash_including('key' => 'includeDevDependencies', 'valueType' => 'BOOLEAN'),
        a_hash_including('key' => 'maxDepth', 'envVar' => 'DS_MAX_DEPTH', 'valueType' => 'INTEGER')
      )
    end

    it 'returns the options of a multi-select variable' do
      post_graphql(query, current_user: user)

      expect(variables).to include(
        a_hash_including(
          'key' => 'disabledResolutionJobs',
          'valueType' => 'MULTI_SELECT',
          'placeholder' => 'Select jobs to skip',
          'options' => [
            { 'value' => 'maven', 'text' => 'Maven' },
            { 'value' => 'gradle', 'text' => 'Gradle' },
            { 'value' => 'python', 'text' => 'Python' }
          ]
        )
      )
    end

    it 'returns the range of an integer variable' do
      post_graphql(query, current_user: user)

      expect(variables).to include(
        a_hash_including('key' => 'maxDepth', 'min' => -1, 'max' => nil),
        a_hash_including('key' => 'apiTimeout', 'min' => 5, 'max' => 300)
      )
    end
  end

  context 'when the scan type has no configuration variables' do
    let(:scan_type) { :DEPENDENCY_SCANNING_POST_PROCESSING }

    it 'returns an empty list' do
      post_graphql(query, current_user: user)

      expect(variables).to eq([])
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :read_metadata do
    let(:boundary_object) { :instance }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
  end
end
