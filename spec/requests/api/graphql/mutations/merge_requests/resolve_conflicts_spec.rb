# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Resolving the conflicts of a merge request', feature_category: :code_review_workflow do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:group) { create(:group) }

  # Not let_it_be: resolving commits to the source branch, and Gitaly changes are not rolled back
  let(:project) { create(:project, :repository, group: group, developers: current_user) }
  let(:merge_status) { :cannot_be_merged }
  let(:merge_request) do
    create(:merge_request, source_project: project, source_branch: 'conflict-resolvable',
      target_branch: 'conflict-start', merge_status: merge_status)
  end

  let(:files) do
    [
      {
        our_path: 'files/ruby/popen.rb',
        their_path: 'files/ruby/popen.rb',
        sections: [{ section_id: '2f6fcd96b88b36ce98c38da085c795a27d92a3dd_14_14', resolution: 'OURS' }]
      },
      {
        our_path: 'files/ruby/regex.rb',
        their_path: 'files/ruby/regex.rb',
        sections: [
          { section_id: '6eb14e00385d2fb284765eb1cd8d420d33d63fc9_9_9', resolution: 'OURS' },
          { section_id: '6eb14e00385d2fb284765eb1cd8d420d33d63fc9_21_21', resolution: 'THEIRS' },
          { section_id: '6eb14e00385d2fb284765eb1cd8d420d33d63fc9_49_49', resolution: 'THEIRS' }
        ]
      }
    ]
  end

  let(:input) { { files: files, commit_message: 'Resolve the conflicts' } }

  let(:mutation) do
    graphql_mutation(
      :merge_request_resolve_conflicts,
      { project_path: project.full_path, iid: merge_request.iid.to_s }.merge(input),
      'errors mergeRequest { id }'
    )
  end

  def mutation_response
    graphql_mutation_response(:merge_request_resolve_conflicts)
  end

  def source_head
    project.repository.commit(merge_request.source_branch)
  end

  def source_content(path)
    project.repository.blob_at(merge_request.source_branch, path).data
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :update_merge_request do
    let(:user) { current_user }
    let(:boundary_object) { project }
    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end

  it 'returns an error when the user cannot update the merge request', :aggregate_failures do
    source_sha = source_head.sha

    post_graphql_mutation(mutation, current_user: create(:user))

    expect(graphql_errors).to include(a_hash_including('message' => a_string_including("you don't have permission")))
    expect(source_head.sha).to eq(source_sha)
  end

  # The ai_workflows scope is covered in ee/spec: FOSS GraphQL only accepts api and read_api tokens
  context 'with an OAuth token with only the read_api scope' do
    let(:oauth_token) { create(:oauth_access_token, user: current_user, scopes: [:read_api]) }

    it 'does not commit', :aggregate_failures do
      source_sha = source_head.sha

      post_graphql_mutation(mutation, token: { oauth_access_token: oauth_token })

      expect(graphql_errors).to be_present
      expect(source_head.sha).to eq(source_sha)
    end
  end

  context 'with the sections conflictFiles returns' do
    let(:sides) { { 'files/ruby/popen.rb' => 'OURS', 'files/ruby/regex.rb' => 'THEIRS' } }
    let(:files) do
      conflict_files.map do |file|
        {
          our_path: file['ourPath'],
          their_path: file['theirPath'],
          sections: file['sections'].map do |section|
            { section_id: section['sectionId'], resolution: sides.fetch(file['ourPath']) }
          end
        }
      end
    end

    let(:conflict_files) do
      post_graphql(
        graphql_query_for(:merge_request, { id: global_id_of(merge_request) },
          'conflictFiles { ourPath theirPath content sections { sectionId } }'),
        current_user: current_user
      )

      graphql_data_at(:merge_request, :conflict_files)
    end

    # The conflict markers with only the kept side left, which is what the web UI commits
    def resolved_content(path, side)
      group = { 'OURS' => 1, 'THEIRS' => 2 }.fetch(side)
      content = conflict_files.find { |file| file['ourPath'] == path }['content']

      content.gsub(/^<{7} [^\n]*\n(.*?)^={7}\n(.*?)^>{7} [^\n]*\n/m) { Regexp.last_match(group) }
    end

    it 'commits a merge of the target branch that keeps the chosen side of each conflict', :aggregate_failures do
      source_sha = source_head.sha
      target_sha = project.repository.commit(merge_request.target_branch).sha
      expected = sides.to_h { |path, side| [path, resolved_content(path, side)] }

      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['mergeRequest']).to eq('id' => merge_request.to_global_id.to_s)
      expect(source_head.message).to eq('Resolve the conflicts')
      expect(source_head.parent_ids).to eq([source_sha, target_sha])
      expected.each { |path, content| expect(source_content(path)).to eq(content) }
    end
  end

  context 'with the content of a file' do
    let(:files) do
      [
        { our_path: 'files/ruby/popen.rb', their_path: 'files/ruby/popen.rb', content: "resolved\n" },
        super().last
      ]
    end

    it 'commits that content', :aggregate_failures do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['errors']).to be_empty
      expect(source_content('files/ruby/popen.rb')).to eq("resolved\n")
    end
  end

  context 'without a commit message' do
    let(:input) { { files: files } }

    it 'uses the commit message of the web UI', :aggregate_failures do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['errors']).to be_empty
      expect(source_head.message).to start_with("Merge branch 'conflict-start' into 'conflict-resolvable'")
    end
  end

  context 'when a file gives both sections and content' do
    let(:files) { [super().first.merge(content: "resolved\n")] }

    it 'is rejected before resolving' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(graphql_errors).to contain_exactly(
        a_hash_including('message' => 'One and only one of [content, sections] arguments is required.')
      )
    end
  end

  context 'when a file gives neither sections nor content' do
    let(:files) { [super().first.except(:sections)] }

    it 'is rejected before resolving' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(graphql_errors).to contain_exactly(
        a_hash_including('message' => 'One and only one of [content, sections] arguments is required.')
      )
    end
  end

  context 'when a file resolves a section more than once' do
    let(:files) do
      popen, regex = super()

      [popen, regex.merge(sections: regex[:sections] + [regex[:sections].first.merge(resolution: 'THEIRS')])]
    end

    it 'is rejected before resolving', :aggregate_failures do
      source_sha = source_head.sha
      message = 'File files/ruby/regex.rb has more than one resolution for section ' \
        '6eb14e00385d2fb284765eb1cd8d420d33d63fc9_9_9.'

      post_graphql_mutation(mutation, current_user: current_user)

      expect(graphql_errors).to contain_exactly(a_hash_including('message' => message))
      expect(source_head.sha).to eq(source_sha)
    end
  end

  shared_examples 'a refused resolution' do
    it 'returns the reason with the merge request and leaves the source branch alone', :aggregate_failures do
      source_sha = source_head.sha

      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['errors']).to eq([message])
      expect(mutation_response['mergeRequest']).to eq('id' => merge_request.to_global_id.to_s)
      expect(source_head.sha).to eq(source_sha)
    end
  end

  context 'when the user cannot push to the source branch' do
    let(:message) { 'Cannot push to source branch' }

    before do
      create(:protected_branch, :no_one_can_push, project: project, name: merge_request.source_branch)
    end

    it_behaves_like 'a refused resolution'
  end

  context 'when the conflicts are already resolved' do
    let(:merge_status) { :can_be_merged }
    let(:message) { 'The merge conflicts for this merge request have already been resolved.' }

    it_behaves_like 'a refused resolution'
  end

  context 'when the mergeability is still being checked' do
    let(:merge_status) { :unchecked }
    let(:message) do
      'The mergeability of this merge request is still being checked. Please try again in a moment.'
    end

    it_behaves_like 'a refused resolution'
  end

  context 'when the conflicts cannot be resolved through GitLab' do
    let(:message) do
      'The merge conflicts for this merge request cannot be resolved through GitLab. ' \
        'Please try to resolve them locally.'
    end

    before do
      allow(Gitlab::Git::Conflict::Parser).to receive(:parse).and_raise(Gitlab::Git::Conflict::Parser::UnmergeableFile)
    end

    it_behaves_like 'a refused resolution'
  end

  context 'when a file is not in conflict' do
    let(:files) { [super().first.merge(our_path: 'files/ruby/typo.rb', their_path: 'files/ruby/typo.rb')] }
    let(:message) { 'File files/ruby/typo.rb is not in conflict.' }

    it_behaves_like 'a refused resolution'
  end

  context 'when a file has no sections' do
    let(:files) { [super().first.merge(sections: [])] }
    let(:message) { 'File files/ruby/popen.rb needs either sections or content.' }

    it_behaves_like 'a refused resolution'
  end

  context 'when a file that cannot be split into sections is given sections' do
    let(:message) { 'File files/ruby/popen.rb can only be resolved with content.' }

    before do
      allow(Gitlab::Git::Conflict::Parser).to receive(:parse).and_call_original
      allow(Gitlab::Git::Conflict::Parser).to receive(:parse)
        .with(anything, a_hash_including(our_path: 'files/ruby/popen.rb'))
        .and_raise(Gitlab::Git::Conflict::Parser::UnexpectedDelimiter)
    end

    it_behaves_like 'a refused resolution'
  end

  context 'when a conflict has no resolution' do
    let(:files) do
      [super().first, super().last.merge(sections: super().last[:sections].first(1))]
    end

    let(:message) { 'Missing resolution for section ID: 6eb14e00385d2fb284765eb1cd8d420d33d63fc9_21_21' }

    it_behaves_like 'a refused resolution'
  end

  context 'when a pre-receive hook rejects the push' do
    let(:message) { 'hook rejected the push' }

    before do
      allow_next_instance_of(Gitlab::Conflict::FileCollection) do |conflicts|
        allow(conflicts).to receive(:resolve)
          .and_raise(Gitlab::Git::PreReceiveError.new('GitLab: hook rejected the push'))
      end
    end

    it_behaves_like 'a refused resolution'
  end
end
