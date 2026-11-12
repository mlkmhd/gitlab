# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Explore::SnippetsController, :with_current_organization, feature_category: :source_code_management do
  describe 'GET #index' do
    let!(:project_snippets) { create_list(:project_snippet, 3, :public) }
    let!(:personal_snippets) { create_list(:personal_snippet, 3, :public) }

    let(:rendered_snippets) { Nokogiri::HTML(response.body).css('[data-testid="snippet-link"]') }

    before do
      allow(Kaminari.config).to receive(:default_per_page).and_return(2)
    end

    it 'renders the first page of personal snippets without a total count', :aggregate_failures do
      get explore_snippets_path

      expect(response).to have_gitlab_http_status(:ok)
      expect(rendered_snippets.size).to eq(2)
      expect(personal_snippet_links).to eq(2)
      expect(response.body).to have_css('[data-testid="kaminari-pagination-next"][rel="next"]')
      expect(response.body).to have_no_css('[data-testid="kaminari-pagination-item"]')
    end

    it 'renders the next page of personal snippets', :aggregate_failures do
      get explore_snippets_path(page: 2)

      expect(response).to have_gitlab_http_status(:ok)
      expect(rendered_snippets.size).to eq(1)
      expect(personal_snippet_links).to eq(1)
      expect(response.body).to have_css('[data-testid="kaminari-pagination-prev"][rel="prev"]')
      expect(response.body).to have_no_css('[data-testid="kaminari-pagination-item"]')
    end

    context 'when signed in' do
      let_it_be(:user) { create(:user, :with_namespace) }

      before do
        sign_in(user)
      end

      it 'avoids N+1 database queries' do
        # Warming call to load everything non snippet related
        get explore_snippets_path

        project = create(:project, namespace: user.namespace)
        create(:project_snippet, project: project, author: user)

        control = ActiveRecord::QueryRecorder.new { get explore_snippets_path }

        project = create(:project, namespace: user.namespace)
        create(:project_snippet, project: project, author: user)

        expect { get explore_snippets_path }.not_to exceed_query_limit(control)
      end
    end

    def personal_snippet_links
      paths = personal_snippets.map { |snippet| snippet_path(snippet) }

      rendered_snippets.count { |item| item.css('a').any? { |link| paths.include?(link['href']) } }
    end
  end
end
