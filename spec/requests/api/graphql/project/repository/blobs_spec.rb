# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'getting blobs in a project repository', feature_category: :source_code_management do
  include GraphqlHelpers

  let(:project) { create(:project, :repository) }
  let(:current_user) { project.first_owner }
  let(:paths) { ["CONTRIBUTING.md", "README.md"] }
  let(:ref) { project.default_branch }
  let(:fields) do
    <<~QUERY
      blobs(paths:#{paths.inspect}, ref:#{ref.inspect}) {
        nodes {
          #{all_graphql_fields_for('repository_blob'.classify)}
        }
      }
    QUERY
  end

  let(:query) do
    graphql_query_for(
      'project',
      { 'fullPath' => project.full_path },
      query_graphql_field('repository', {}, fields)
    )
  end

  subject(:blobs) { graphql_data_at(:project, :repository, :blobs, :nodes) }

  it 'returns the blob' do
    post_graphql(query, current_user: current_user)

    expect(blobs).to match_array(paths.map { |path| a_hash_including('path' => path) })
  end

  describe 'auxiliaryViewer' do
    let(:paths) { %w[LICENSE files/ruby/regex.rb] }
    let(:fields) do
      <<~QUERY
        blobs(paths:#{paths.inspect}, ref:#{ref.inspect}) {
          nodes {
            path
            auxiliaryViewer { type fileType }
          }
        }
      QUERY
    end

    it 'returns the auxiliary viewer only for blobs that show one' do
      post_graphql(query, current_user: current_user)

      expect(blobs).to contain_exactly(
        { 'path' => 'LICENSE', 'auxiliaryViewer' => { 'type' => 'auxiliary', 'fileType' => 'license' } },
        { 'path' => 'files/ruby/regex.rb', 'auxiliaryViewer' => nil }
      )
    end

    context 'when the README notice depends on wiki access' do
      let(:project) { create(:project, :repository, :public, :wiki_private, :wiki_repo_with_page) }
      let(:paths) { %w[README.md] }

      it 'returns the auxiliary viewer to a user who can read the wiki' do
        post_graphql(query, current_user: project.first_owner)

        expect(blobs).to contain_exactly(
          { 'path' => 'README.md', 'auxiliaryViewer' => { 'type' => 'auxiliary', 'fileType' => 'readme' } }
        )
      end

      it 'returns no auxiliary viewer to a user who cannot read the wiki' do
        post_graphql(query, current_user: create(:user))

        expect(blobs).to contain_exactly({ 'path' => 'README.md', 'auxiliaryViewer' => nil })
      end
    end

    it 'avoids N+1 queries for more blobs with an auxiliary viewer' do
      control_paths = %w[LICENSE CHANGELOG CONTRIBUTING.md README]
      post_graphql(query_for_paths(control_paths), current_user: current_user) # warm-up
      control = ActiveRecord::QueryRecorder.new do
        post_graphql(query_for_paths(control_paths), current_user: current_user)
      end

      query = query_for_paths(control_paths + %w[README.md files/ruby/regex.rb])

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(control)
    end

    def query_for_paths(blob_paths)
      graphql_query_for(
        'project',
        { 'fullPath' => project.full_path },
        query_graphql_field('repository', {}, <<~QUERY)
          blobs(paths:#{blob_paths.inspect}, ref:#{ref.inspect}) {
            nodes {
              path
              auxiliaryViewer { type }
            }
          }
        QUERY
      )
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL',
    [:read_project, :read_code, :read_repository_blob] do
    let(:user) { current_user }
    let(:boundary_object) { project }
    let(:query) do
      graphql_query_for(
        'project',
        { 'fullPath' => project.full_path },
        query_graphql_field('repository', {}, <<~GQL)
          blobs(paths:#{paths.inspect}, ref:#{ref.inspect}) {
            nodes {
              path
              name
            }
          }
        GQL
      )
    end

    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
  end
end
