# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'POST /api/v4/jobs/request with an Artifact Registry credential', :clean_gitlab_redis_shared_state,
  feature_category: :artifact_registry do
  include StubGitlabCalls

  describe 'POST /api/v4/jobs/request' do
    let_it_be(:cloud_connector_key) { create(:cloud_connector_keys) }
    let_it_be(:organization) { create(:organization) }
    let_it_be(:user) { create(:user) }
    let_it_be(:project) { create(:project, :empty_repo, organization: organization, shared_runners_enabled: false) }
    let_it_be(:runner) { create(:ci_runner, :project, projects: [project]) }

    let(:pipeline) { create(:ci_pipeline, project: project, ref: 'master') }
    let!(:job) { create(:ci_build, :pending, :queued, pipeline: pipeline, user: user) }
    let(:executor) { 'docker' }

    let(:artifact_registry_credential) do
      json_response['credentials'].find { |credential| credential['url'] == 'registry.example.com:5050' }
    end

    before_all do
      create(:organization_user, organization: organization, user: user)
      create(:artifact_registry_namespace_mapping, organization: organization)
    end

    before do
      stub_gitlab_calls
      stub_config(artifact_registry: { api_url: 'https://registry.example.com:5050' })
      # CachingKeyLoader memoizes Keys.current at the class level; pin it to ours.
      allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk).and_return(cloud_connector_key.to_jwk)
    end

    def request_job
      post api('/jobs/request'),
        params: { token: runner.token, system_id: 's_artifact_registry', info: { executor: executor } }.to_json,
        headers: { 'User-Agent' => 'gitlab-runner 19.5.0 (19-5-stable; go1.24; linux/amd64)',
                   'Content-Type' => 'application/json' }
    end

    it 'sends a registry credential for the Artifact Registry host', :aggregate_failures do
      request_job

      expect(response).to have_gitlab_http_status(:created)
      expect(artifact_registry_credential).to include('type' => 'registry', 'username' => 'gitlab-ci-token')

      payload, = JWT.decode(artifact_registry_credential['password'], cloud_connector_key.public_key, true,
        algorithm: 'RS256')
      expect(payload['sub']).to eq(user.to_global_id.to_s)
      expect(payload['gitlab']).to include('origin_id' => organization.uuid)
    end

    context 'when the runner reports the Kubernetes executor' do
      let(:executor) { 'kubernetes' }

      it 'sends no Artifact Registry credential' do
        request_job

        expect(response).to have_gitlab_http_status(:created)
        expect(artifact_registry_credential).to be_nil
      end
    end

    context 'when the token issuer raises' do
      before do
        allow_next_instance_of(::Authn::TokenExchange::TokenIssuer) do |issuer|
          allow(issuer).to receive(:token).and_raise(StandardError, 'no signing key')
        end
      end

      it 'still sends the job, without the Artifact Registry credential', :aggregate_failures do
        allow(::Gitlab::ErrorTracking).to receive(:log_exception)

        request_job

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response['id']).to eq(job.id)
        expect(artifact_registry_credential).to be_nil
        expect(::Gitlab::ErrorTracking).to have_received(:log_exception)
          .with(
            have_attributes(message: 'no signing key'),
            { Labkit::Fields::GL_PROJECT_ID => project.id, job_id: job.id }
          )
      end
    end

    context 'when the job request runs out of time while the credential is issued' do
      before do
        allow_next_instance_of(::Authn::TokenExchange::TokenIssuer) do |issuer|
          allow(issuer).to receive(:token).and_raise(::Ci::RegisterJobService::PresentBuildTimeoutError)
        end
      end

      it 'drops the job as a scheduler failure', :aggregate_failures do
        allow(::Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception)
        # Dropping a job takes about 110 queries in this setup with or without the credential,
        # over the default of 100; the credential adds the organization, mapping and membership reads.
        allow(::Gitlab::QueryLimiting::Transaction).to receive(:threshold).and_return(125)

        request_job

        expect(response).to have_gitlab_http_status(:no_content)
        expect(job.reload).to be_failed
        expect(job.failure_reason).to eq('scheduler_failure')
      end
    end
  end
end
