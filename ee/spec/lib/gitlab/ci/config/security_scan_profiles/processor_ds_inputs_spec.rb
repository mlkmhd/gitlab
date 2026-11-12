# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ci::Config::SecurityScanProfiles::Processor, 'Dependency Scanning spec:inputs',
  feature_category: :security_testing_configuration do
  let_it_be(:namespace) { create(:group) }
  let_it_be_with_reload(:project) { create(:project, :small_repo, group: namespace) }

  let(:config) { { image: 'image:1.0.0' } }
  let(:ref) { "refs/heads/#{project.default_branch}" }
  let(:source) { :push }
  let(:scan_profile_context) do
    Gitlab::Ci::Pipeline::SecurityScanProfiles::PipelineContext.new(
      project: project, ref: ref, pipeline_source: source)
  end

  let(:ci_context) do
    Gitlab::Ci::Config::External::Context.new(project: project).tap do |ctx|
      ctx.scan_profile_context = scan_profile_context
    end
  end

  let(:configuration_values) { nil }
  let(:result) { perform_service }
  let(:job) { result.fetch(:'dependency-scanning-profile-0') }
  let(:resolution_jobs) { result.slice(*result.keys.grep(/resolution-profile/)).values }
  let(:template_path) { Rails.root.join('lib/gitlab/ci/templates/Jobs/Dependency-Scanning.v2.gitlab-ci.yml') }
  let(:template_inputs) { YAML.load_stream(File.read(template_path)).first.dig('spec', 'inputs') }
  let(:certificate) do
    <<~PEM.chomp
      -----BEGIN CERTIFICATE-----
      MIIDdzCCAl+gAwIBAgIEAgAAuTANBgkqhkiG9w0BAQUFADBaMQswCQYDVQQGEwJJ
      RTESMBAGA1UEChMJQmFsdGltb3JlMRMwEQYDVQQLEwpDeWJlclRydXN0MSIwIAYD
      VQQDExlCYWx0aW1vcmUgQ3liZXJUcnVzdCBSb290MB4XDTAwMDUxMjE4NDYwMFoX
      DTI1MDUxMjIzNTkwMFowWjELMAkGA1UEBhMCSUUxEjAQBgNVBAoTCUJhbHRpbW9y
      ZTETMBEGA1UECxMKQ3liZXJUcnVzdDEiMCAGA1UEAxMZQmFsdGltb3JlIEN5YmVy
      -----END CERTIFICATE-----
    PEM
  end

  let_it_be(:profile) do
    create(:security_scan_profile, namespace: namespace, name: 'DS', scan_type: :dependency_scanning,
      projects: [project])
  end

  let!(:trigger) do
    create(:security_scan_profile_trigger, namespace: namespace, scan_profile: profile,
      configuration_values: configuration_values)
  end

  subject(:perform_service) { described_class.new(config, ci_context, ref, source).perform }

  before do
    stub_licensed_features(security_scan_profiles: true)
  end

  def export_line(job, name)
    job[:script].find { |line| line.start_with?("export #{name}=") }
  end

  def export_fallback(job, name)
    export_line(job, name)&.[](/:-(.*)\}"\z/m, 1)
  end

  def template_default(input)
    template_inputs.dig(input, 'default').to_s
  end

  # Skips schema validation so payloads the schema rejects still reach the processor.
  def store_raw_configuration(values)
    trigger.configuration.update_column(:configuration, values)
  end

  context 'when no configuration is stored' do
    it 'renders the template defaults and sets no profile variables', :aggregate_failures do
      expect(export_fallback(job, 'DS_MAX_DEPTH')).to eq(template_default('max_scan_depth'))
      expect(export_fallback(job, 'DS_INCLUDE_DEV_DEPENDENCIES')).to eq(template_default('include_dev_dependencies'))
      expect(job[:variables]).not_to include(:DS_MAX_DEPTH)
    end
  end

  context 'when the configuration maps to several inputs' do
    let(:configuration_values) do
      {
        max_depth: 5, include_dev_dependencies: false, excluded_paths: %w[docs tmp],
        static_reachability_enabled: true, disabled_resolution_jobs: %w[maven],
        maven_resolution_image: 'registry.example.com/maven:1',
        gradle_resolution_image: 'registry.example.com/gradle:1',
        python_resolution_image: 'registry.example.com/python:1', api_timeout: 20, secure_log_level: 'debug',
        pip_manifest_file_name_pattern: 'requirements*.txt', pipcompile_lockfile_file_name_pattern: 'pip.lock'
      }
    end

    it 'renders the inputs as fallbacks, keeps the env vars and disables only maven', :aggregate_failures do
      expect(export_fallback(job, 'DS_MAX_DEPTH')).to eq('5')
      expect(export_fallback(job, 'DS_EXCLUDED_PATHS')).to eq('docs,tmp')
      expect(export_fallback(job, 'DS_INCLUDE_DEV_DEPENDENCIES')).to eq('false')
      expect(export_fallback(job, 'DS_STATIC_REACHABILITY_ENABLED')).to eq('true')
      expect(export_fallback(job, 'DS_API_TIMEOUT')).to eq('20')
      expect(export_fallback(job, 'SECURE_LOG_LEVEL')).to eq('debug')
      expect(export_fallback(job, 'DS_PIP_MANIFEST_FILE_NAME_PATTERN')).to eq('requirements*.txt')
      expect(export_fallback(job, 'DS_PIPCOMPILE_LOCKFILE_FILE_NAME_PATTERN')).to eq('pip.lock')
      expect(job[:variables]).to include(
        DS_MAX_DEPTH: '5', DS_EXCLUDED_PATHS: 'docs,tmp', DS_INCLUDE_DEV_DEPENDENCIES: 'false',
        DS_STATIC_REACHABILITY_ENABLED: 'true', DS_API_TIMEOUT: '20', SECURE_LOG_LEVEL: 'debug'
      )

      expect(resolution_jobs.size).to eq(3)
      resolution_jobs.each do |resolution_job|
        expect(export_fallback(resolution_job, 'DS_MAX_DEPTH')).to eq('5')
        expect(export_fallback(resolution_job, 'DS_EXCLUDED_PATHS')).to eq('docs,tmp')
        expect(resolution_job[:variables]).to include(DS_MAX_DEPTH: '5', DS_EXCLUDED_PATHS: 'docs,tmp')
      end
      expect(resolution_jobs.map { |j| j[:variables].slice(:DS_MAVEN_RESOLUTION_IMAGE, :DS_PYTHON_RESOLUTION_IMAGE) }
        .reduce(:merge)).to eq(
          DS_MAVEN_RESOLUTION_IMAGE: 'registry.example.com/maven:1',
          DS_PYTHON_RESOLUTION_IMAGE: 'registry.example.com/python:1')

      maven_rule = result.fetch(:'dependency-scanning:maven-resolution-profile-0')[:rules].first
      expect(maven_rule).to include(when: 'never', if: match(/\A"maven" =~/))
      %i[python gradle].each do |type|
        rule = result.fetch(:"dependency-scanning:#{type}-resolution-profile-0")[:rules].first
        expect(rule[:if]).to start_with('"maven" =~').and include("/\\b#{type}\\b/")
      end
    end
  end

  context 'when an analyzer image prefix is stored' do
    let(:configuration_values) { { secure_analyzers_prefix: 'registry.example.com/mirror' } }

    it 'passes it through the env var only, so a project variable can still override it', :aggregate_failures do
      expect(job[:variables]).to include(SECURE_ANALYZERS_PREFIX: 'registry.example.com/mirror')
      expect(job[:variables][:DS_ANALYZER_IMAGE]).to eq('$SECURE_ANALYZERS_PREFIX/dependency-scanning:2')
    end
  end

  context 'when no analyzer image version is stored' do
    let(:jobs) { [job, *resolution_jobs] }

    it 'uses the template default tag in every job', :aggregate_failures do
      default_tag = template_default('analyzer_image_version')

      expect(jobs.size).to eq(4)
      jobs.each { |job| expect(job[:variables][:DS_ANALYZER_IMAGE]).to end_with("/dependency-scanning:#{default_tag}") }
    end
  end

  context 'when an analyzer image version is stored' do
    let(:configuration_values) { { analyzer_image_version: '3' } }
    let(:jobs) { [job, *resolution_jobs] }

    it 'uses the tag in the main job and every resolution job', :aggregate_failures do
      expect(jobs.size).to eq(4)
      jobs.each { |job| expect(job[:variables][:DS_ANALYZER_IMAGE]).to end_with('/dependency-scanning:3') }
    end
  end

  context 'when a multi-line CA bundle is stored' do
    let(:configuration_values) { { additional_ca_cert_bundle: certificate } }

    it 'passes the CA bundle through the env var only', :aggregate_failures do
      expect(job[:variables]).to include(ADDITIONAL_CA_CERT_BUNDLE: certificate)
      expect(export_line(job, 'ADDITIONAL_CA_CERT_BUNDLE'))
        .to eq('export ADDITIONAL_CA_CERT_BUNDLE="${ADDITIONAL_CA_CERT_BUNDLE:-}"')
      expect(job[:script].join("\n")).not_to include('BEGIN CERTIFICATE')
    end
  end

  context 'with hostile string values' do
    let(:payloads) do
      [
        'a"b', 'a$b', 'a`id`b', 'a\\b', "a'b", 'x}', "a\n- curl evil", '$[[ inputs.max_scan_depth ]]',
        'docs" ; curl evil #'
      ]
    end

    let(:string_keys) do
      [
        [:excluded_paths, 'DS_EXCLUDED_PATHS', 'excluded_paths'],
        [:pip_manifest_file_name_pattern, 'DS_PIP_MANIFEST_FILE_NAME_PATTERN', 'pip_manifest_file_name_pattern'],
        [:pipcompile_lockfile_file_name_pattern, 'DS_PIPCOMPILE_LOCKFILE_FILE_NAME_PATTERN',
          'pipcompile_lockfile_file_name_pattern'],
        [:maven_dependency_plugin_version, 'DS_MAVEN_DEPENDENCY_PLUGIN_VERSION', 'maven_dependency_plugin_version'],
        [:maven_resolution_image, nil, nil],
        [:gradle_resolution_image, nil, nil],
        [:python_resolution_image, nil, nil],
        [:analyzer_image_version, nil, nil],
        [:secure_log_level, 'SECURE_LOG_LEVEL', 'analyzer_log_level']
      ]
    end

    [0, 5, 9].each do |offset|
      context "with payload assignment #{offset}" do
        let(:assignment) do
          string_keys.each_with_index.to_h { |(key, *), index| [key, payloads[(offset + index) % payloads.size]] }
        end

        let(:configuration_values) { { max_depth: 1 } }
        let(:jobs) { [job, *resolution_jobs] }
        let(:text) { jobs.flat_map { |j| j[:script] + j[:rules].filter_map { |rule| rule[:if] } }.join("\n") }

        before do
          store_raw_configuration(assignment)
        end

        it 'drops every payload from the scripts and rules and keeps the template fallbacks', :aggregate_failures do
          expect(jobs.size).to eq(4)
          expect(text).not_to include('curl')
          assignment.each_value { |payload| expect(text).not_to include(payload) }

          string_keys.each do |key, env, input|
            next unless env

            fallbacks = jobs.filter_map { |j| export_fallback(j, env) }

            expect(fallbacks).not_to be_empty, "no #{env} export line"
            expect(fallbacks.uniq).to eq([template_default(input)]), "#{key} fallback changed"
          end
          jobs.each do |j|
            expect(j[:variables][:DS_ANALYZER_IMAGE]).to eq('$SECURE_ANALYZERS_PREFIX/dependency-scanning:2')
          end
        end
      end
    end

    context 'when disabled_resolution_jobs holds a quote breakout' do
      let(:configuration_values) { { max_depth: 1 } }

      before do
        store_raw_configuration('disabled_resolution_jobs' => ['maven" || "1" == "1'])
      end

      it 'keeps every resolution rule on the empty default', :aggregate_failures do
        %i[maven python gradle].each do |type|
          rule = result.fetch(:"dependency-scanning:#{type}-resolution-profile-0")[:rules].first

          expect(rule[:if]).to eq(%("" =~ /\\b#{type}\\b/ || $DS_DISABLED_RESOLUTION_JOBS =~ /\\b#{type}\\b/))
        end
        expect(job[:variables]).to include(DS_DISABLED_RESOLUTION_JOBS: 'maven" || "1" == "1')
      end
    end

    context 'when a pip pattern holds a single quote or a closing brace' do
      let(:configuration_values) do
        { pip_manifest_file_name_pattern: "a'b", pipcompile_lockfile_file_name_pattern: 'x}' }
      end

      it 'renders empty fallbacks and keeps the env vars', :aggregate_failures do
        expect(export_line(job, 'DS_PIP_MANIFEST_FILE_NAME_PATTERN'))
          .to eq('export DS_PIP_MANIFEST_FILE_NAME_PATTERN="${DS_PIP_MANIFEST_FILE_NAME_PATTERN:-}"')
        expect(export_line(job, 'DS_PIPCOMPILE_LOCKFILE_FILE_NAME_PATTERN'))
          .to eq('export DS_PIPCOMPILE_LOCKFILE_FILE_NAME_PATTERN="${DS_PIPCOMPILE_LOCKFILE_FILE_NAME_PATTERN:-}"')
        expect(job[:variables])
          .to include(DS_PIP_MANIFEST_FILE_NAME_PATTERN: "a'b", DS_PIPCOMPILE_LOCKFILE_FILE_NAME_PATTERN: 'x}')
      end
    end
  end

  context 'with a hostile value in a boolean or number key' do
    let(:configuration_values) { { max_depth: 1 } }

    before do
      store_raw_configuration('max_depth' => '1"; curl evil #', 'include_dev_dependencies' => 'true"; curl evil #')
    end

    it 'fails the pipeline build instead of rendering the value' do
      expect { perform_service }.to raise_error(Gitlab::Ci::Config::ConfigError, /pipeline cannot run/)
    end
  end

  context 'with two dependency scanning profiles in one pipeline' do
    let_it_be(:other_profile) do
      create(:security_scan_profile, namespace: namespace, name: 'DS other', scan_type: :dependency_scanning,
        projects: [project])
    end

    let(:configuration_values) { { max_depth: 3, analyzer_image_version: '3' } }

    let!(:other_trigger) do
      create(:security_scan_profile_trigger, namespace: namespace, scan_profile: other_profile,
        configuration_values: { max_depth: 9, analyzer_image_version: '4' })
    end

    let(:jobs) { result.slice(:'dependency-scanning-profile-0', :'dependency-scanning-profile-1').values }

    it 'keeps each job on its own value', :aggregate_failures do
      expect(jobs.size).to eq(2)
      expect(jobs.map { |job| [job[:variables][:DS_MAX_DEPTH], export_fallback(job, 'DS_MAX_DEPTH')] })
        .to contain_exactly(
          %w[3 3],
          %w[9 9]
        )
      expect(jobs.map { |job| [job[:variables][:DS_MAX_DEPTH], job[:variables][:DS_ANALYZER_IMAGE].split(':').last] })
        .to contain_exactly(%w[3 3], %w[9 4])
    end
  end
end
