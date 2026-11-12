# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::GraphsController, feature_category: :source_code_management do
  let_it_be(:project) { create(:project, :small_repo, :private) }
  let(:ref) { 'master' }

  describe 'GET #charts' do
    subject(:send_request) { get charts_project_graph_path(project, ref), params: params }

    let(:params) { {} }

    context 'when user is unauthorized' do
      it 'shows 404' do
        send_request
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when user is authorized' do
      let(:user) { project.creator }

      before do
        sign_in(user)
      end

      it 'renders content' do
        send_request
        expect(response).to be_successful
      end

      context 'when path includes a space' do
        let(:params) { { path: 'a b' } }

        it 'still renders the page' do
          send_request

          expect(response).to have_gitlab_http_status(:ok)
        end
      end
    end
  end

  describe 'GET #show' do
    # `sha~1` needs a repository with more than one commit to resolve
    let_it_be(:project) { create(:project, :repository, :private) }

    before do
      sign_in(project.creator)
    end

    # Percent-encoded characters bypass the route's git_reference_regex constraint,
    # and Gitaly happily resolves revision syntax such as `sha~1`
    context 'when ref is not a valid git reference' do
      where(:encoded_ref) do
        [
          'master%7E1',
          lazy { "#{project.commit.short_id}%7E1" }
        ]
      end

      with_them do
        it 'returns 404' do
          get "/#{project.full_path}/-/graphs/#{encoded_ref}"

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end
  end
end
