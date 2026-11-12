# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ci::Build::Credentials::Registry::ArtifactRegistry, feature_category: :artifact_registry do
  let_it_be(:cloud_connector_key) { create(:cloud_connector_keys) }
  let_it_be(:organization) { create(:organization) }
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, organization: organization) }
  let_it_be(:runner) { create(:ci_runner, :project, projects: [project]) }

  let(:executor_type) { :docker }
  let(:runner_manager) { create(:ci_runner_machine, runner: runner, executor_type: executor_type) }
  let(:started_at) { Time.current }
  let(:timeout) { 1.hour.to_i }
  let(:build) do
    create(:ci_build, :running, project: project, user: user, started_at: started_at, timeout: timeout)
  end

  let(:counter) { instance_double(Prometheus::Client::Counter, increment: nil) }

  subject(:credential) { described_class.new(build) }

  before_all do
    create(:organization_user, organization: organization, user: user)
    create(:artifact_registry_namespace_mapping, organization: organization)
  end

  around do |example|
    freeze_time { example.run }
  end

  before do
    # CachingKeyLoader memoizes Keys.current at the class level; pin it to ours.
    allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk).and_return(cloud_connector_key.to_jwk)
    allow(described_class).to receive(:counter).and_return(counter)
    stub_config(artifact_registry: { api_url: 'https://registry.example.com:5050' })
    build.runner_manager = runner_manager
  end

  def decoded_token
    JWT.decode(credential.password, cloud_connector_key.public_key, true, algorithm: 'RS256').first
  end

  it 'has the shape of the other registry credentials', :aggregate_failures do
    expect(credential.type).to eq('registry')
    expect(credential.url).to eq('registry.example.com:5050')
    expect(credential.username).to eq(::Gitlab::Auth::CI_JOB_USER)
  end

  context 'when every condition holds' do
    it 'issues a token for the job user and the project organization', :aggregate_failures do
      expect(credential).to be_valid

      expect(decoded_token).to include(
        'aud' => %w[gitlab-artifact-registry gitlab-iam-data-access],
        'sub' => user.to_global_id.to_s
      )
      expect(decoded_token['gitlab']).to include('origin_id' => organization.uuid, 'local_id' => user.id)
    end

    it 'carries no job claims' do
      expect(decoded_token['gitlab'].keys.grep(/\Ajob/)).to be_empty
      expect(decoded_token.keys.grep(/\Ajob/)).to be_empty
    end

    it 'expires at the job start plus its timeout' do
      expect(decoded_token['exp']).to eq((started_at + timeout.seconds).to_i)
    end

    it 'counts the issued credential' do
      credential.valid?

      expect(counter).to have_received(:increment).with(result: 'issued', reason: '')
    end

    it 'issues the token once' do
      expect(::Authn::TokenExchange::TokenIssuer).to receive(:new).once.and_call_original

      credential.valid?
      credential.password
    end

    context 'when the job timeout is longer than 12 hours' do
      let(:timeout) { 24.hours.to_i }

      it 'clamps the lifetime to 12 hours' do
        expect(decoded_token['exp'] - decoded_token['iat']).to eq(12.hours.to_i)
      end
    end
  end

  shared_examples 'a skipped credential' do |reason|
    it "carries no credential and counts the skip as #{reason}", :aggregate_failures do
      expect(::Authn::TokenExchange::TokenIssuer).not_to receive(:new)

      expect(credential).not_to be_valid
      expect(counter).to have_received(:increment).with(result: 'skipped', reason: reason)
    end
  end

  context 'when the Artifact Registry is not configured' do
    before do
      stub_config(artifact_registry: { api_url: nil })
    end

    it_behaves_like 'a skipped credential', 'not_configured'

    it 'has no url' do
      expect(credential.url).to be_nil
    end
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(ci_artifact_registry_pull_credentials: false)
    end

    it_behaves_like 'a skipped credential', 'flag_disabled'
  end

  context 'when the runner manager reports the Kubernetes executor' do
    let(:executor_type) { :kubernetes }

    it_behaves_like 'a skipped credential', 'kubernetes_executor'
  end

  context 'when the runner manager reports no known executor' do
    let(:executor_type) { :unknown }

    it_behaves_like 'a skipped credential', 'unknown_executor'
  end

  context 'when the job has no runner manager' do
    let(:runner_manager) { nil }

    it_behaves_like 'a skipped credential', 'unknown_executor'
  end

  context 'when the project organization has not activated the Artifact Registry' do
    let_it_be(:other_organization) { create(:organization) }
    let_it_be(:project) { create(:project, organization: other_organization) }
    let_it_be(:runner) { create(:ci_runner, :project, projects: [project]) }

    before_all do
      create(:organization_user, organization: other_organization, user: user)
    end

    it_behaves_like 'a skipped credential', 'not_activated'
  end

  context 'when the job user is not a member of the project organization' do
    let(:build) do
      create(:ci_build, :running, project: project, user: create(:user), started_at: started_at, timeout: timeout)
    end

    it_behaves_like 'a skipped credential', 'not_member'
  end

  context 'when the job has no user' do
    let(:build) do
      create(:ci_build, :running, project: project, user: nil, started_at: started_at, timeout: timeout)
    end

    it_behaves_like 'a skipped credential', 'not_member'
  end

  context 'when the token issuer raises' do
    let(:error) { StandardError.new('no signing key') }

    before do
      allow_next_instance_of(::Authn::TokenExchange::TokenIssuer) do |issuer|
        allow(issuer).to receive(:token).and_raise(error)
      end
    end

    it 'skips the credential and logs the error', :aggregate_failures do
      expect(::Gitlab::ErrorTracking).to receive(:log_exception)
        .with(error, { Labkit::Fields::GL_PROJECT_ID => project.id, job_id: build.id })

      expect(credential).not_to be_valid
      expect(counter).to have_received(:increment).with(result: 'skipped', reason: 'error')
    end

    it 'does not send the error to error tracking, which runs inside the phase timer' do
      expect(::Gitlab::ErrorTracking).not_to receive(:track_exception)

      credential.valid?
    end
  end

  context 'when a database check raises' do
    let(:error) { ActiveRecord::QueryCanceled.new('canceling statement due to statement timeout') }

    before do
      allow(user).to receive(:member_of_organization?).and_raise(error)
    end

    it 'skips the credential and logs the error', :aggregate_failures do
      expect(::Authn::TokenExchange::TokenIssuer).not_to receive(:new)
      expect(::Gitlab::ErrorTracking).to receive(:log_exception)
        .with(error, { Labkit::Fields::GL_PROJECT_ID => project.id, job_id: build.id })

      expect(credential).not_to be_valid
      expect(counter).to have_received(:increment).with(result: 'skipped', reason: 'error')
    end
  end

  context 'when the job request runs out of time while the token is issued' do
    before do
      allow_next_instance_of(::Authn::TokenExchange::TokenIssuer) do |issuer|
        allow(issuer).to receive(:token).and_raise(::Ci::RegisterJobService::PresentBuildTimeoutError)
      end
    end

    it 're-raises the phase timeout without counting it' do
      expect(::Gitlab::ErrorTracking).not_to receive(:log_exception)

      expect { credential.valid? }.to raise_error(::Ci::RegisterJobService::PresentBuildTimeoutError)
      expect(counter).not_to have_received(:increment)
    end
  end
end
