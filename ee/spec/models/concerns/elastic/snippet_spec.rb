# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Snippet, :elastic, feature_category: :global_search do
  before do
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
  end

  it 'always returns global result for Elasticsearch indexing for #use_elasticsearch?' do
    snippet = create :personal_snippet

    expect(snippet.use_elasticsearch?).to be(true)

    stub_ee_application_setting(elasticsearch_indexing: false)

    expect(snippet.use_elasticsearch?).to be(false)
  end

  it 'searches snippets by title and description' do
    user = create(:user)

    Sidekiq::Testing.inline! do
      create(:personal_snippet, :public, title: 'home')
      create(:personal_snippet, :private, title: 'home 1')
      create(:personal_snippet, :public, description: 'a test snippet')
      create(:personal_snippet)

      ensure_elasticsearch_index!
    end

    options = { current_user: user }

    expect(described_class.elastic_search('home', options: options).total_count).to eq(1)
    expect(described_class.elastic_search('test snippet', options: options).total_count).to eq(1)
  end

  describe 'public and internal project snippets for a non-member' do
    let_it_be(:user) { create(:user) }
    let_it_be(:project) { create(:project, :public) }
    let_it_be(:snippet) { create(:project_snippet, :public, project: project, title: 'visible project snippet') }

    before do
      Sidekiq::Testing.inline! do
        snippet.maintain_elasticsearch_update
        ensure_elasticsearch_index!
      end
    end

    it 'finds the snippet' do
      expect(described_class.elastic_search('visible', options: { current_user: user }).total_count).to eq(1)
    end

    context 'when the backfill migration has not finished' do
      before do
        set_elasticsearch_migration_to(:backfill_project_access_on_snippets, including: false)
      end

      it 'does not find the snippet' do
        expect(described_class.elastic_search('visible', options: { current_user: user }).total_count).to eq(0)
      end
    end
  end

  it "names elasticsearch queries" do
    described_class.elastic_search('*').total_count

    assert_named_queries('doc:is_a:snippet', 'snippet:match:search_terms', 'snippet:authorized')
  end

  it 'returns json with all needed elements' do
    snippet = create(:project_snippet, author: create(:user, :banned))

    expected_hash = snippet.attributes.extract!(
      'id',
      'title',
      'created_at',
      'description',
      'updated_at',
      'state',
      'project_id',
      'author_id',
      'visibility_level'
    ).merge({
      'type' => snippet.es_type,
      'schema_version' => Elastic::Latest::SnippetInstanceProxy::SCHEMA_VERSION,
      'project_visibility_level' => snippet.project.visibility_level,
      'snippets_access_level' => snippet.project.project_feature.snippets_access_level,
      'organization_id' => snippet.project.organization_id,
      'hidden' => true
    })

    expect(snippet.__elasticsearch__.as_indexed_json).to eq(expected_hash)
  end

  it 'preloads the author, the project and its project feature for indexing' do
    create(:project_snippet)

    snippet = described_class.preload_indexing_data.first

    expect(snippet.association(:author)).to be_loaded
    expect(snippet.association(:project)).to be_loaded
    expect(snippet.project.association(:project_feature)).to be_loaded
  end

  it 'uses same index for Snippet subclasses', :eager_load do
    Snippet.subclasses.each do |snippet_class|
      expect(snippet_class.index_name).to eq(Snippet.index_name)
      expect(snippet_class.document_type).to eq(Snippet.document_type)
      expect(snippet_class.__elasticsearch__.mappings.to_hash).to eq(Snippet.__elasticsearch__.mappings.to_hash)
    end
  end
end
