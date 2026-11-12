# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::TerraformController, feature_category: :infrastructure_as_code do
  let_it_be(:project) { create(:project, :public) }

  describe 'GET index' do
    subject(:get_index) { get project_terraform_index_path(project) }

    context 'when user is authorized' do
      let(:user) { project.creator }

      before do
        sign_in(user)
        get_index
      end

      it 'renders content' do
        expect(response).to be_successful
      end

      it 'pushes the terraform_state_delayed_deletion feature flag' do
        expect(response.body).to have_pushed_frontend_feature_flags(terraformStateDelayedDeletion: true)
      end
    end

    context 'when user is unauthorized' do
      let(:user) { create(:user, guest_of: project) }

      before do
        sign_in(user)
        get_index
      end

      it 'shows 404' do
        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when no user is present' do
      before do
        get_index
      end

      it 'shows 404' do
        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end
end
