# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DependencyManagement::SecurityUpdate::RepositoryConfig, feature_category: :dependency_management do
  let_it_be(:project) { create(:project, :repository) }

  let(:content) { nil }
  let(:config) { described_class.new(project) }
  let(:path) { described_class::CONFIG_PATH }

  before do
    blob = content && instance_double(Gitlab::Git::Blob, size: content.bytesize, data: content)

    allow(project.repository).to receive(:blob_at)
      .with("refs/heads/#{project.repository.root_ref}", path, limit: described_class::MAX_FILE_SIZE)
      .and_return(blob)
  end

  shared_examples 'a rejected config' do |message|
    it 'is invalid and exposes nothing' do
      expect(config).not_to be_valid
      expect(config.error).to eq("`#{path}` #{message}")
      expect(config.credentials).to be_empty
      expect(config.variables).to be_empty
    end
  end

  shared_examples 'an empty config' do
    it 'is valid and exposes nothing' do
      expect(config).to be_valid
      expect(config.error).to be_nil
      expect(config.credentials).to be_empty
      expect(config.variables).to be_empty
    end
  end

  context 'when the file is absent' do
    it_behaves_like 'an empty config'
  end

  context 'when the file is empty' do
    let(:content) { '' }

    it_behaves_like 'an empty config'
  end

  context 'when the file holds only comments' do
    let(:content) { "# nothing here yet\n" }

    it_behaves_like 'an empty config'
  end

  context 'when the file has no registries' do
    let(:content) { "registries: {}\n" }

    it_behaves_like 'an empty config'
  end

  context 'when registries is left blank' do
    let(:content) { "registries:\n" }

    it_behaves_like 'an empty config'
  end

  context 'when the repository has no root ref' do
    let(:content) { 'registries: {}' }

    before do
      allow(project.repository).to receive(:root_ref).and_return(nil)
    end

    it 'does not read a blob' do
      expect(project.repository).not_to receive(:blob_at)

      expect(config).to be_valid
    end
  end

  context 'when the file is committed to the default branch' do
    let(:project) { create(:project, :repository) }

    before do
      allow(project.repository).to receive(:blob_at).and_call_original
    end

    def commit_config(data)
      project.repository.create_file(
        project.owner, path, data, message: 'Add config', branch_name: project.default_branch
      )
    end

    it 'reads it from the repository' do
      commit_config(<<~YAML)
        registries:
          gitlab-npm:
            kind: npm
            url: "https://gitlab.example.com/npm/"
            password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
      YAML

      expect(config.variables).to eq(%w[DS_AUTO_REMEDIATION_NPM_TOKEN])
    end

    it 'rejects an oversized file without loading all of it' do
      commit_config("# #{'a' * described_class::MAX_FILE_SIZE}\n")

      expect(project.repository).to receive(:blob_at)
        .with("refs/heads/#{project.repository.root_ref}", path, limit: described_class::MAX_FILE_SIZE)
        .and_call_original
      expect(config.error).to eq("`#{path}` is larger than #{described_class::MAX_FILE_SIZE} bytes")
    end

    it 'reads the branch, not a tag with the same name' do
      commit_config("registries: {}\n")
      project.repository.create_file(
        project.owner, path, "registries: []\n", message: 'Tagged config', branch_name: 'tagged-config'
      )
      project.repository.add_tag(project.owner, project.default_branch, 'tagged-config')

      expect(config).to be_valid
    end
  end

  describe 'file-level validation' do
    context 'when the YAML is malformed' do
      let(:content) { "registries:\n  foo: bar\n :\n" }

      it 'is invalid and names the file' do
        expect(config).not_to be_valid
        expect(config.error).to start_with("`#{path}` is not valid YAML:")
      end
    end

    {
      'a float tag on a word' => '!!float nope',
      'a float tag on nothing' => '!!float',
      'a string tag on a mapping' => '!!str {x: 1}'
    }.each do |description, value|
      context "when a tagged scalar is #{description}" do
        let(:content) { "registries:\n  gitlab-npm:\n    replaces-base: #{value}\n" }

        it 'is invalid' do
          expect(config).not_to be_valid
          expect(config.error).to start_with("`#{path}` is not valid YAML:")
        end
      end
    end

    context 'when a registry repeats a key' do
      let(:content) do
        <<~YAML
          registries:
            gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/"
              url: "https://attacker.example.com/npm/"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config', 'repeats the key "url"'
    end

    context 'when a key is a sequence' do
      let(:content) { "? [registries]\n: {}\n" }

      it_behaves_like 'a rejected config', 'has unsupported keys: "[\\"registries\\"]"'
    end

    context 'when a registry merges in a mapping' do
      let(:content) do
        <<~YAML
          registries:
            gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
              <<: {url: "https://attacker.example.com/npm/"}
        YAML
      end

      it_behaves_like 'a rejected config', 'must not use the `<<` merge key'
    end

    context 'when the merge key is quoted' do
      let(:content) { "registries:\n  \"<<\": {}\n" }

      it_behaves_like 'a rejected config', 'must not use the `<<` merge key'
    end

    context 'when a registry name is repeated' do
      let(:content) do
        <<~YAML
          registries:
            gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
            gitlab-npm:
              kind: npm
              url: "https://other.example.com/npm/"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config', 'repeats the key "gitlab-npm"'
    end

    context 'when the file holds more than one document' do
      let(:content) { "registries: {}\n---\nallowEnv: []\n" }

      it_behaves_like 'a rejected config', 'must hold a single YAML document'
    end

    context 'when an empty document comes first' do
      let(:content) { "---\n---\nregistries: {}\n" }

      it_behaves_like 'a rejected config', 'must hold a single YAML document'
    end

    context 'when the document is not a mapping' do
      let(:content) { "- registries\n" }

      it_behaves_like 'a rejected config', 'must be a mapping'
    end

    context 'when the document has unsupported keys' do
      let(:content) { "registries: {}\nregistry: {}\nallowEnv: []\n" }

      it_behaves_like 'a rejected config', 'has unsupported keys: "allowEnv", "registry"'
    end

    context 'when the file is oversized' do
      let(:content) { "# #{'a' * described_class::MAX_FILE_SIZE}\nregistries: {}\n" }

      it_behaves_like 'a rejected config', "is larger than #{described_class::MAX_FILE_SIZE} bytes"
    end

    context 'when the YAML uses aliases' do
      let(:content) { "defaults: &a {}\nregistries: *a\n" }

      it 'is invalid' do
        expect(config).not_to be_valid
        expect(config.error).to start_with("`#{path}` is not valid YAML:")
      end
    end

    context 'when the YAML nests deep enough to overflow the parser' do
      let(:content) { "registries: #{'[' * 5000}#{']' * 5000}\n" }

      it_behaves_like 'a rejected config', "nests deeper than #{described_class::MAX_YAML_DEPTH} levels"
    end

    context 'when an unsupported key is long' do
      let(:content) { "registries: {}\n#{'k' * 100}: 1\n" }

      it_behaves_like 'a rejected config', "has unsupported keys: \"#{'k' * 46}..."
    end

    context 'when unsupported keys mix text and binary' do
      let(:content) { "registries: {}\n\u00e4: 1\n? !!binary /w==\n: 1\n" }

      it_behaves_like 'a rejected config', "has unsupported keys: \"\u00e4\", \"\\xFF\""

      it 'gives an error that serializes to JSON' do
        expect { Gitlab::Json.dump(error: config.error) }.not_to raise_error
      end
    end
  end

  describe 'registries' do
    let(:content) do
      <<~YAML
        registries:
          #{registry}
      YAML
    end

    let(:registry) { '' }

    context 'with an npm registry' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/api/v4/projects/1/packages/npm/"
              username: "gitlab-ci-token"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
              replaces-base: true
        YAML
      end

      it 'maps onto npm_registry with the scheme stripped and a basic-auth token' do
        expect(config).to be_valid
        expect(config.credentials).to eq([{
          'type' => 'npm_registry',
          'registry' => 'gitlab.example.com/api/v4/projects/1/packages/npm/',
          'token' => 'gitlab-ci-token:${DS_AUTO_REMEDIATION_NPM_TOKEN}',
          'replaces-base' => true
        }])
        expect(config.variables).to eq(%w[DS_AUTO_REMEDIATION_NPM_TOKEN])
      end
    end

    context 'with an npm registry and no username' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/api/v4/projects/1/packages/npm/"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it 'sends the password as a bearer token' do
        expect(config.credentials).to eq([{
          'type' => 'npm_registry',
          'registry' => 'gitlab.example.com/api/v4/projects/1/packages/npm/',
          'token' => '${DS_AUTO_REMEDIATION_NPM_TOKEN}'
        }])
      end
    end

    context 'with an npm registry whose scheme is upper case' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "HTTPS://gitlab.example.com/api/v4/projects/1/packages/npm/"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it 'still strips the scheme' do
        expect(config.credentials.first['registry']).to eq('gitlab.example.com/api/v4/projects/1/packages/npm/')
      end
    end

    context 'with an npm registry whose username contains a colon' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/api/v4/projects/1/packages/npm/"
              username: "ci:bot"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `gitlab-npm` of kind `npm` must not have `:` in `username`'
    end

    context 'with an npm registry whose username is a placeholder' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/"
              username: "${DS_AUTO_REMEDIATION_NPM_USER}"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `gitlab-npm` of kind `npm` must set `username` to a literal value'
    end

    context 'with a username given as YAML binary' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/api/v4/projects/1/packages/npm/"
              username: !!binary /w==
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `gitlab-npm` must set `username` to printable text'
    end

    context 'with a username holding a control character' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/api/v4/projects/1/packages/npm/"
              username: "ci\\nbot"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `gitlab-npm` must set `username` to printable text'
    end

    context 'with a maven registry' do
      let(:registry) do
        <<~YAML.chomp
          internal-maven:
              kind: maven
              url: "https://maven.example.com/repository/internal"
              username: "ci"
              password: "${DS_AUTO_REMEDIATION_MAVEN_PASSWORD}"
        YAML
      end

      it 'maps onto maven_repository keeping the scheme and the username/password pair' do
        expect(config.credentials).to eq([{
          'type' => 'maven_repository',
          'url' => 'https://maven.example.com/repository/internal',
          'username' => 'ci',
          'password' => '${DS_AUTO_REMEDIATION_MAVEN_PASSWORD}'
        }])
      end
    end

    context 'with a maven registry missing a username' do
      let(:registry) do
        <<~YAML.chomp
          internal-maven:
              kind: maven
              url: "https://maven.example.com/repository/internal"
              password: "${DS_AUTO_REMEDIATION_MAVEN_PASSWORD}"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `internal-maven` of kind `maven` must set `username`'
    end

    context 'with a python registry' do
      let(:registry) do
        <<~YAML.chomp
          internal-pypi:
              kind: python
              url: "https://pypi.example.com/simple"
              password: "${DS_AUTO_REMEDIATION_PYPI_TOKEN}"
        YAML
      end

      it 'maps onto python_index keeping the scheme' do
        expect(config.credentials).to eq([{
          'type' => 'python_index',
          'index-url' => 'https://pypi.example.com/simple',
          'token' => '${DS_AUTO_REMEDIATION_PYPI_TOKEN}'
        }])
      end
    end

    context 'with a python registry and a literal username' do
      let(:registry) do
        <<~YAML.chomp
          internal-pypi:
              kind: python
              url: "https://pypi.example.com/simple"
              username: "ci-bot"
              password: "${DS_AUTO_REMEDIATION_PYPI_TOKEN}"
        YAML
      end

      it 'joins the username into the token' do
        expect(config.credentials.first['token']).to eq('ci-bot:${DS_AUTO_REMEDIATION_PYPI_TOKEN}')
        expect(config.variables).to eq(%w[DS_AUTO_REMEDIATION_PYPI_TOKEN])
      end
    end

    context 'with replaces-base set to false' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
              replaces-base: false
        YAML
      end

      it 'keeps it' do
        expect(config.credentials.first['replaces-base']).to be(false)
      end
    end

    context 'when a valid registry is followed by an invalid one' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
            internal-maven:
              kind: maven
              url: "https://maven.example.com/repository/internal"
              password: "${DS_AUTO_REMEDIATION_MAVEN_PASSWORD}"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `internal-maven` of kind `maven` must set `username`'
    end

    context 'with a username placeholder' do
      let(:registry) do
        <<~YAML.chomp
          internal-maven:
              kind: maven
              url: "https://maven.example.com/repository/internal"
              username: "${DS_AUTO_REMEDIATION_MAVEN_USER}"
              password: "${DS_AUTO_REMEDIATION_MAVEN_PASSWORD}"
        YAML
      end

      it 'keeps the placeholder unresolved and exposes both variables' do
        expect(config.credentials.first['username']).to eq('${DS_AUTO_REMEDIATION_MAVEN_USER}')
        expect(config.variables).to eq(%w[DS_AUTO_REMEDIATION_MAVEN_USER DS_AUTO_REMEDIATION_MAVEN_PASSWORD])
      end
    end

    context 'with several registries sharing a variable' do
      let(:registry) do
        <<~YAML.chomp
          npm-one:
              kind: npm
              url: "https://gitlab.example.com/npm/1"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
            npm-two:
              kind: npm
              url: "https://gitlab.example.com/npm/2"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
            internal-pypi:
              kind: python
              url: "https://pypi.example.com/simple"
              password: "${DS_AUTO_REMEDIATION_PYPI_TOKEN}"
        YAML
      end

      it 'exposes each referenced variable once' do
        expect(config.credentials.size).to eq(3)
        expect(config.variables).to eq(%w[DS_AUTO_REMEDIATION_NPM_TOKEN DS_AUTO_REMEDIATION_PYPI_TOKEN])
      end
    end

    context 'when it is not a mapping' do
      let(:content) { "registries:\n  - kind: npm\n" }

      it_behaves_like 'a rejected config', '`registries` must be a mapping'
    end

    context 'when a registry is not a mapping' do
      let(:registry) { 'gitlab-npm: "https://gitlab.example.com"' }

      it_behaves_like 'a rejected config', 'registry `gitlab-npm` must be a mapping'
    end

    context 'when a registry name is unusable' do
      let(:registry) { "\"a registry/name\":\n      kind: npm" }

      it 'is invalid' do
        expect(config).not_to be_valid
        expect(config.error).to include('must be alphanumeric, with dots, dashes or underscores')
      end
    end

    context 'when a registry name is read as a boolean' do
      let(:registry) { "on:\n      kind: npm" }

      it_behaves_like 'a rejected config', 'registry name true must be a string, so quote it'
    end

    context 'when a registry has unsupported keys' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
              token: "glpat-literal"
              scope: "@acme"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `gitlab-npm` has unsupported keys: "scope", "token"'
    end

    context 'when the kind is unsupported' do
      let(:registry) do
        <<~YAML.chomp
          feed:
              kind: nuget
              url: "https://nuget.example.com/v3/index.json"
              password: "${DS_AUTO_REMEDIATION_NUGET_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `feed` must set `kind` to one of: npm, maven, python'
    end

    context 'when the URL is missing' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `gitlab-npm` must set `url` to a string'
    end

    context 'when the URL is not https' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "http://gitlab.example.com/npm/"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `gitlab-npm` must set `url` to an `https://` address'
    end

    context 'when the URL embeds credentials' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://user:glpat-literal@gitlab.example.com/npm/"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config',
        'registry `gitlab-npm` must not embed credentials in `url`; use `username` and `password`'
    end

    context 'when the URL has an empty userinfo' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://@gitlab.example.com/npm/"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config',
        'registry `gitlab-npm` must not embed credentials in `url`; use `username` and `password`'
    end

    context 'when the URL path holds an npm scope' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/@acme/npm/"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it 'is not mistaken for embedded credentials' do
        expect(config).to be_valid
        expect(config.credentials.first['registry']).to eq('gitlab.example.com/@acme/npm/')
      end
    end

    context 'when the URL has a query' do
      let(:registry) do
        <<~YAML.chomp
          internal-maven:
              kind: maven
              url: "https://maven.example.com/m?private_token=glpat-literal"
              username: "ci"
              password: "${DS_AUTO_REMEDIATION_MAVEN_PASSWORD}"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `internal-maven` must not have a query or fragment in `url`'
    end

    context 'when the URL has a fragment' do
      let(:registry) do
        <<~YAML.chomp
          internal-maven:
              kind: maven
              url: "https://maven.example.com/m#glpat-literal"
              username: "ci"
              password: "${DS_AUTO_REMEDIATION_MAVEN_PASSWORD}"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `internal-maven` must not have a query or fragment in `url`'
    end

    context 'when the URL references a variable' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/?private_token=${DS_AUTO_REMEDIATION_NPM_TOKEN}"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `gitlab-npm` must not reference a variable in `url`'
    end

    context 'when the URL path references a variable' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/${DS_AUTO_REMEDIATION_NPM_TOKEN}/npm/"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `gitlab-npm` must not reference a variable in `url`'
    end

    context 'when the URL is exactly at the length cap' do
      let(:url) { "https://gitlab.example.com/#{'a' * (described_class::MAX_URL_LENGTH - 27)}" }
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "#{url}"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it 'is valid' do
        expect(url.length).to eq(described_class::MAX_URL_LENGTH)
        expect(config).to be_valid
      end
    end

    context 'when the URL is over the length cap' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/#{'a' * described_class::MAX_URL_LENGTH}"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config',
        "registry `gitlab-npm` has a `url` over #{described_class::MAX_URL_LENGTH} characters"
    end

    context 'when the URL is malformed' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/a b c"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `gitlab-npm` has a malformed `url`'
    end

    context 'when the password is missing' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `gitlab-npm` must set `password` to a string'
    end

    context 'when the username is not a string' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/"
              username: 42
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `gitlab-npm` must set `username` to a string'
    end

    context 'when the password is a literal' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/"
              password: "glpat-not-a-placeholder"
        YAML
      end

      it_behaves_like 'a rejected config',
        'registry `gitlab-npm` must set `password` to a `${VARIABLE}` placeholder, not a literal value'
    end

    context 'when the password interpolates more than a placeholder' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/"
              password: "Bearer ${DS_AUTO_REMEDIATION_NPM_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config',
        'registry `gitlab-npm` must set `password` to a `${VARIABLE}` placeholder, not a literal value'
    end

    context 'when the password references a variable outside the prefix' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/"
              password: "${PRODUCTION_DEPLOY_TOKEN}"
        YAML
      end

      it_behaves_like 'a rejected config',
        'registry `gitlab-npm` references `PRODUCTION_DEPLOY_TOKEN` in `password`, which is not an ' \
          'upper-case variable name prefixed with `DS_AUTO_REMEDIATION_`'
    end

    context 'when the password references a variable GitLab sets on the job' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/"
              password: "${DEPENDENCY_MANAGEMENT_TARGET_REF}"
        YAML
      end

      it 'is invalid' do
        expect(config).not_to be_valid
        expect(config.error).to include('prefixed with `DS_AUTO_REMEDIATION_`')
      end
    end

    context 'when the password references a lower-case variable' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/"
              password: "${DS_AUTO_REMEDIATION_npm_token}"
        YAML
      end

      it 'is invalid' do
        expect(config).not_to be_valid
        expect(config.error).to include('which is not an upper-case variable name')
      end
    end

    context 'when the password references only the prefix' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/"
              password: "${DS_AUTO_REMEDIATION_}"
        YAML
      end

      it 'is invalid' do
        expect(config).not_to be_valid
      end
    end

    context 'when the password references a variable longer than the variable name column allows' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/"
              password: "${DS_AUTO_REMEDIATION_#{'A' * described_class::MAX_VARIABLE_NAME_LENGTH}}"
        YAML
      end

      it 'is invalid and does not echo the whole name' do
        expect(config).not_to be_valid
        expect(config.error).to include('which is not an upper-case variable name')
        expect(config.error.length).to be < 250
      end
    end

    context 'when the username looks like a placeholder but is malformed' do
      let(:registry) do
        <<~YAML.chomp
          internal-maven:
              kind: maven
              url: "https://maven.example.com/repository/internal"
              username: "$DS_AUTO_REMEDIATION_MAVEN_USER"
              password: "${DS_AUTO_REMEDIATION_MAVEN_PASSWORD}"
        YAML
      end

      it_behaves_like 'a rejected config',
        'registry `internal-maven` must set `username` to a `${VARIABLE}` placeholder, not a literal value'
    end

    context 'when the username embeds a placeholder after a literal' do
      let(:registry) do
        <<~YAML.chomp
          internal-maven:
              kind: maven
              url: "https://maven.example.com/repository/internal"
              username: "ci${CI_JOB_TOKEN}"
              password: "${DS_AUTO_REMEDIATION_MAVEN_PASSWORD}"
        YAML
      end

      it_behaves_like 'a rejected config',
        'registry `internal-maven` must set `username` to a `${VARIABLE}` placeholder, not a literal value'
    end

    context 'when the username references a variable outside the prefix' do
      let(:registry) do
        <<~YAML.chomp
          internal-maven:
              kind: maven
              url: "https://maven.example.com/repository/internal"
              username: "${CI_REGISTRY_USER}"
              password: "${DS_AUTO_REMEDIATION_MAVEN_PASSWORD}"
        YAML
      end

      it 'is invalid' do
        expect(config).not_to be_valid
        expect(config.error).to include('references `CI_REGISTRY_USER` in `username`')
      end
    end

    context 'when replaces-base is not a boolean' do
      let(:registry) do
        <<~YAML.chomp
          gitlab-npm:
              kind: npm
              url: "https://gitlab.example.com/npm/"
              password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
              replaces-base: "yes"
        YAML
      end

      it_behaves_like 'a rejected config', 'registry `gitlab-npm` must set `replaces-base` to true or false'
    end

    context 'when there are exactly as many registries as the cap' do
      let(:registry) do
        (1..described_class::MAX_REGISTRIES).map do |i|
          <<~YAML.chomp
            registry-#{i}:
                  kind: npm
                  url: "https://gitlab.example.com/npm/#{i}"
                  password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
          YAML
        end.join("\n  ")
      end

      it 'is valid' do
        expect(config.credentials.size).to eq(described_class::MAX_REGISTRIES)
      end
    end

    context 'when there are more registries than the cap' do
      let(:registry) do
        (1..described_class::MAX_REGISTRIES.next).map do |i|
          <<~YAML.chomp
            registry-#{i}:
                  kind: npm
                  url: "https://gitlab.example.com/npm/#{i}"
                  password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
          YAML
        end.join("\n  ")
      end

      it_behaves_like 'a rejected config',
        "`registries` defines more than #{described_class::MAX_REGISTRIES} registries"
    end
  end

  describe 'caching', :request_store do
    let(:content) do
      <<~YAML
        registries:
          gitlab-npm:
            kind: npm
            url: "https://gitlab.example.com/npm/"
            password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
      YAML
    end

    it 'reads the blob once for the same project' do
      expect(project.repository).to receive(:blob_at).once
        .and_return(instance_double(Gitlab::Git::Blob, size: content.bytesize, data: content))

      2.times { expect(described_class.new(project).variables).to eq(%w[DS_AUTO_REMEDIATION_NPM_TOKEN]) }
    end
  end

  describe 'secret handling' do
    let(:content) do
      <<~YAML
        registries:
          gitlab-npm:
            kind: npm
            url: "https://gitlab.example.com/npm/"
            password: "${DS_AUTO_REMEDIATION_NPM_TOKEN}"
      YAML
    end

    it 'never resolves a placeholder against the process environment' do
      stub_env('DS_AUTO_REMEDIATION_NPM_TOKEN', 'the-real-secret')

      expect(config.credentials.to_s).not_to include('the-real-secret')
      expect(config.credentials.first['token']).to eq('${DS_AUTO_REMEDIATION_NPM_TOKEN}')
    end
  end
end
