# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'POST /internal/ci/job_router/jobs/request with an Artifact Registry credential',
  :clean_gitlab_redis_shared_state, feature_category: :artifact_registry do
  include StubGitlabCalls

  let_it_be(:cloud_connector_key) { create(:cloud_connector_keys) }
  let_it_be(:organization) { create(:organization) }
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :empty_repo, organization: organization, shared_runners_enabled: true) }
  let_it_be(:runner) { create(:ci_runner, :instance) }

  let(:pipeline) { create(:ci_pipeline, project: project, ref: 'master') }
  let!(:job) { create(:ci_build, :pending, :queued, pipeline: pipeline, user: user) }

  let(:jwt_secret) { SecureRandom.random_bytes(Gitlab::Kas::SECRET_LENGTH) }
  let(:jwt_token) do
    JWT.encode({ 'iss' => Gitlab::Kas::JWT_ISSUER, 'aud' => Gitlab::Kas::JWT_AUDIENCE }, jwt_secret, 'HS256')
  end

  before_all do
    create(:organization_user, organization: organization, user: user)
    create(:artifact_registry_namespace_mapping, organization: organization)
  end

  before do
    allow(Gitlab::Kas).to receive_messages(enabled?: true, secret: jwt_secret)
    stub_gitlab_calls
    stub_config(artifact_registry: { api_url: 'https://registry.example.com:5050' })
    # CachingKeyLoader memoizes Keys.current at the class level; pin it to ours.
    allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk).and_return(cloud_connector_key.to_jwk)
  end

  it 'sends the credential and issues one token for the job', :aggregate_failures do
    expect(::Authn::TokenExchange::TokenIssuer).to receive(:new).once.and_call_original

    post api('/internal/ci/job_router/jobs/request'),
      params: { token: runner.token, system_id: 's_artifact_registry', info: { executor: 'docker' } }.to_json,
      headers: { Gitlab::Kas::INTERNAL_API_KAS_REQUEST_HEADER => jwt_token, 'Content-Type' => 'application/json' }

    expect(response).to have_gitlab_http_status(:created)
    expect(json_response['credentials'])
      .to include(a_hash_including('url' => 'registry.example.com:5050', 'username' => 'gitlab-ci-token'))
  end
end
