# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::Ci::PipelineEditorController, feature_category: :pipeline_composition do
  let_it_be(:developer) { create(:user) }
  let_it_be(:reporter) { create(:user, :with_namespace) }
  let_it_be(:project) { create(:project, :small_repo, developers: developer, reporters: reporter) }

  subject(:show_request) { get project_ci_pipeline_editor_path(project) }

  describe 'GET #show' do
    context 'with enough privileges' do
      before do
        sign_in(developer)
        show_request
      end

      it { expect(response).to have_gitlab_http_status(:ok) }

      it 'renders show page' do
        expect(response.body).to have_css('#js-pipeline-editor')
      end
    end

    context 'without enough privileges' do
      before do
        sign_in(reporter)
        show_request
      end

      it 'responds with 404' do
        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end
end
