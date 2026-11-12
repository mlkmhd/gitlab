# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Ml::MlflowArtifacts::Entrypoint, feature_category: :mlops do
  let_it_be(:project) { create(:project) }
  let_it_be(:developer) { create(:user, developer_of: project) }
  let_it_be(:token) { create(:personal_access_token, scopes: %w[api], user: developer) }

  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }
  let(:base_route) { "/projects/#{project.id}/ml/mlflow/api/2.0/mlflow-artifacts" }

  describe 'GET artifacts' do
    let(:request) { get api("#{base_route}/artifacts"), params: { path: %w[a b] }, headers: headers }

    it 'returns INVALID_PARAMETER_VALUE with the validation message', :aggregate_failures do
      request

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response).to eq('error_code' => 'INVALID_PARAMETER_VALUE', 'message' => 'path is invalid')
    end
  end
end
