# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RemoteDevelopment::WorkspacesController, feature_category: :workspaces do
  let_it_be(:user) { create(:user) }

  before do
    sign_in(user)
  end

  describe 'GET /-/remote_development/workspaces' do
    context 'with remote development licensed' do
      before do
        stub_licensed_features(remote_development: true)
      end

      it 'responds with ok' do
        get remote_development_workspaces_path

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'with remote development not licensed' do
      before do
        stub_licensed_features(remote_development: false)
      end

      it 'responds with not found' do
        get remote_development_workspaces_path

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end
end
