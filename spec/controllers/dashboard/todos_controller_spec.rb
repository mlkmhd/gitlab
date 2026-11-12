# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dashboard::TodosController, feature_category: :notifications do
  let_it_be(:user) { create(:user) }

  before do
    sign_in(user)
  end

  describe 'GET #index' do
    it 'renders the index view' do
      get :index

      expect(response).to render_template(:index)
    end

    context 'with the review_decision_todo_actions feature flag' do
      render_views

      it 'pushes the feature flag to the frontend' do
        get :index

        expect(response.body).to have_pushed_frontend_feature_flags(reviewDecisionTodoActions: true)
      end

      it 'pushes the disabled feature flag to the frontend' do
        stub_feature_flags(review_decision_todo_actions: false)

        get :index

        expect(response.body).to have_pushed_frontend_feature_flags(reviewDecisionTodoActions: false)
      end
    end

    context 'external authorization' do
      subject { get :index }

      it_behaves_like 'disabled when using an external authorization service'
    end

    it_behaves_like 'internal event tracking' do
      subject { get :index }

      let(:event) { 'view_todo_list' }
      let(:category) { described_class.name }
      let(:user) { create(:user) }
    end
  end
end
