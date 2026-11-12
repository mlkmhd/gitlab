# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanProfiles::Configuration::CiInputs, feature_category: :security_testing_configuration do
  describe '.build' do
    def build_inputs(config)
      described_class.build(:dependency_scanning, config)
    end

    context 'with every dependency_scanning key' do
      let(:config) do
        {
          excluded_paths: ['a'], max_depth: -1,
          include_dev_dependencies: true, static_reachability_enabled: true, enable_manifest_fallback: false,
          disabled_resolution_jobs: %w[maven python], maven_resolution_image: 'm:1', gradle_resolution_image: 'g:1',
          python_resolution_image: 'p:1', api_timeout: 2.5, secure_log_level: 'debug',
          enable_vulnerability_scan: false, api_scan_download_delay: 0, maven_dependency_plugin_version: '3.7.0',
          pip_manifest_file_name_pattern: 'requirements*.txt', pipcompile_lockfile_file_name_pattern: '*.lock',
          analyzer_image_version: '3'
        }
      end

      let(:result) { build_inputs(config) }

      it 'maps each to its input name', :aggregate_failures do
        expect(result[:max_scan_depth]).to be(-1)
        expect(result).to eq(
          excluded_paths: 'a', max_scan_depth: -1,
          include_dev_dependencies: true, enable_static_reachability: true, enable_manifest_fallback: false,
          disabled_resolution_jobs: 'maven,python', maven_resolution_image: 'm:1', gradle_resolution_image: 'g:1',
          python_resolution_image: 'p:1', vulnerability_scan_api_timeout: 2.5, analyzer_log_level: 'debug',
          enable_vulnerability_scan: false, vulnerability_scan_api_download_delay: 0,
          maven_dependency_plugin_version: '3.7.0', pip_manifest_file_name_pattern: 'requirements*.txt',
          pipcompile_lockfile_file_name_pattern: '*.lock', analyzer_image_version: '3'
        )
      end
    end

    it 'resolves both symbol and string config keys' do
      expect(build_inputs({ 'secure_log_level' => 'debug' })).to eq(analyzer_log_level: 'debug')
    end

    it 'returns an empty hash for unmapped input', :aggregate_failures do
      expect(build_inputs({})).to eq({})
      expect(build_inputs(nil)).to eq({})
      expect(build_inputs({ max_depth: nil })).to eq({})
      expect(build_inputs({ pip_index_url: 'https://x', maven_args: '-X', additional_ca_cert_bundle: 'x' })).to eq({})
      expect(build_inputs({ secure_analyzers_prefix: 'registry.example.com' })).to eq({})
      expect(described_class.build(:unknown_scan, { max_depth: 1 })).to eq({})
      expect(described_class.build(nil, { max_depth: 1 })).to eq({})
    end

    context 'with a non-dependency-scanning scan type' do
      let(:config) { { max_depth: 1, excluded_paths: %w[a] } }

      it 'returns an empty hash', :aggregate_failures do
        %i[sast secret_detection container_scanning].each do |scan_type|
          expect(described_class.build(scan_type, config)).to eq({})
        end
      end
    end

    context 'with non-string values for string inputs' do
      let(:config) { { secure_log_level: 3, excluded_paths: [{ a: 1 }], maven_resolution_image: { a: 1 } } }

      it 'drops them' do
        expect(build_inputs(config)).to eq({})
      end
    end

    it 'leaves booleans and numbers to the JSON schema and the CI input validation', :aggregate_failures do
      expect(build_inputs({ include_dev_dependencies: 'yes', max_depth: 'deep' }))
        .to eq(include_dev_dependencies: 'yes', max_scan_depth: 'deep')
    end

    it 'has a guard for every mapped type' do
      mapped_types = described_class::MAPPINGS.values.flat_map { |mappings| mappings.values.pluck(:type) }.uniq

      expect(described_class::GUARDS.keys).to include(*mapped_types)
    end

    it 'drops blank strings so the template default applies', :aggregate_failures do
      expect(build_inputs({ secure_log_level: '' })).to eq({})
      expect(build_inputs({ excluded_paths: [] })).to eq({})
    end

    context 'with benign punctuation in a string' do
      let(:value) { 'registry.example.com:5000/group/sub-group_1~x@y' }

      it 'keeps it' do
        expect(build_inputs({ maven_resolution_image: value })).to eq(maven_resolution_image: value)
      end
    end

    describe 'string guard' do
      let(:unsafe_values) do
        {
          'double quote' => 'a"b', 'single quote' => "a'b", 'dollar' => 'a$b', 'interpolation' => '$[[ inputs.x ]]',
          'backtick' => 'a`id`b', 'backslash' => 'a\\b', 'closing brace' => 'x}', 'newline' => "a\nb",
          'trailing newline' => "ok\n", 'carriage return' => "a\rb", 'tab' => "a\tb", 'NUL' => "a\0b",
          'DEL' => "a\x7Fb"
        }
      end

      let(:string_keys) do
        described_class::MAPPINGS[:dependency_scanning].select { |_, d| d[:type] == :string }.keys
      end

      let(:limit) { described_class::MAX_LENGTH }

      it 'drops every unsafe value from plain string inputs', :aggregate_failures do
        string_keys.each do |key|
          unsafe_values.each do |name, value|
            expect(build_inputs({ key => value })).to eq({}), "expected #{key} with #{name} to be dropped"
          end
        end
      end

      it 'drops unsafe values inside array items', :aggregate_failures do
        %i[excluded_paths disabled_resolution_jobs].each do |key|
          unsafe_values.each do |name, value|
            expect(build_inputs({ key => ['safe', value] })).to eq({}),
              "expected #{key} item with #{name} to be dropped"
          end
        end
      end

      it 'handles scalar strings and a payload that closes the expansion early', :aggregate_failures do
        expect(build_inputs({ excluded_paths: 'a"b' })).to eq({})
        expect(build_inputs({ excluded_paths: 'solo' })).to eq(excluded_paths: 'solo')
        expect(build_inputs({ excluded_paths: ['x}', '**/*', ''] })).to eq({})
      end

      it 'enforces the length cap at the boundary', :aggregate_failures do
        expect(build_inputs({ secure_log_level: 'a' * limit })).to eq(analyzer_log_level: 'a' * limit)
        expect(build_inputs({ secure_log_level: 'a' * (limit + 1) })).to eq({})
        expect(build_inputs({ excluded_paths: ['a' * (limit + 1)] })).to eq({})
      end

      it 'returns nothing instead of raising for non-UTF-8 strings', :aggregate_failures do
        ["a\xFF".b, "a\xFF".b.force_encoding('UTF-8'), 'abc'.encode('UTF-16LE')].each do |value|
          expect(build_inputs({ secure_log_level: value })).to eq({})
          expect(build_inputs({ excluded_paths: [value] })).to eq({})
        end
      end
    end
  end

  describe 'drift against the Dependency-Scanning.v2 template' do
    let(:template_path) { Rails.root.join('lib/gitlab/ci/templates/Jobs/Dependency-Scanning.v2.gitlab-ci.yml') }
    let(:spec_inputs) { YAML.load_stream(File.read(template_path)).first.dig('spec', 'inputs') }
    let(:type_names) { { string: 'string', comma_separated_strings: 'string', number: 'number', boolean: 'boolean' } }
    let(:samples) { { string: 'x.example.com', number: 7, boolean: true, comma_separated_strings: %w[a b] } }
    let(:mappings) { described_class::MAPPINGS[:dependency_scanning] }
    let(:env_mappings) { Security::ScanProfiles::Configuration::ScanProfileVariables::MAPPINGS[:dependency_scanning] }
    let(:config) { mappings.transform_values { |definition| samples.fetch(definition[:type]) } }

    let(:rendered) do
      Security::SecurityOrchestrationPolicies::TemplateCacheService.new
        .fetch('dependency_scanning', template: 'v2', inputs: described_class.build(:dependency_scanning, config))
        .to_s
    end

    it 'maps only inputs declared by the template, with matching types', :aggregate_failures do
      described_class::MAPPINGS[:dependency_scanning].each_value do |definition|
        input = spec_inputs[definition[:input].to_s]

        expect(input).to be_present, "template has no input #{definition[:input]}"
        expect(input['type']).to eq(type_names.fetch(definition[:type]))
        expect(input.keys).not_to include('options', 'regex')
      end
    end

    it 'keeps the env var of every mapped key readable in the rendered config', :aggregate_failures do
      mappings.except(:analyzer_image_version).each_key do |key|
        env = env_mappings.fetch(key)[:env]

        expect(rendered).to match(/\$\{?#{env}\b/), "#{env} is no longer read once #{key} is passed as an input"
      end
    end
  end
end
