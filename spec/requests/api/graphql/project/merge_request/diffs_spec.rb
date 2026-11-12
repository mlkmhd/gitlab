# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.project.mergeRequest.diffs', feature_category: :code_review_workflow do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :private, :repository) }
  let_it_be(:developer) { create(:user, developer_of: project) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project) }

  let(:diff_args) { '' }

  let(:query) do
    <<~GQL
      query($path: ID!, $iid: String!) {
        project(fullPath: $path) {
          mergeRequest(iid: $iid) {
            iid
            diffs#{diff_args} {
              nodes {
                oldPath
                newPath
                aMode
                bMode
                newFile
                renamedFile
                deletedFile
                collapsed
                tooLarge
                diff
              }
              pageInfo {
                hasNextPage
                endCursor
                hasPreviousPage
                startCursor
              }
              overflow
            }
          }
        }
      }
    GQL
  end

  let(:diffs_path) { %i[project mergeRequest diffs] }

  def run_query(current_user)
    post_graphql(query, current_user: current_user,
      variables: { path: project.full_path, iid: merge_request.iid.to_s })
  end

  context 'when the current user can read the merge request' do
    it 'returns per-file diffs including the raw patch text', :aggregate_failures do
      run_query(developer)

      nodes = graphql_data_at(*diffs_path, :nodes)

      expect(nodes).to be_present
      expect(nodes).to all(include('newPath' => be_present))
      expect(nodes.map { |node| node['diff'] }.join).to include('@@')
    end
  end

  describe 'pagination' do
    let(:diff_args) { '(first: 1)' }

    it 'returns a single page and advertises the next one', :aggregate_failures do
      run_query(developer)

      cursor = graphql_data_at(*diffs_path, :pageInfo, :endCursor)

      expect(graphql_data_at(*diffs_path, :nodes).size).to eq(1)
      expect(graphql_data_at(*diffs_path, :pageInfo, :hasNextPage)).to be(true)
      expect(cursor).to be_present
      expect(GitlabSchema.cursor_encoder.decode(cursor)).to eq('2')
    end

    it 'returns different files across consecutive pages', :aggregate_failures do
      run_query(developer)
      first_page = graphql_data_at(*diffs_path, :nodes).map { |node| node['newPath'] }
      cursor = graphql_data_at(*diffs_path, :pageInfo, :endCursor)

      second_query = query.sub('(first: 1)', %[(first: 1, after: "#{cursor}")])
      post_graphql(second_query, current_user: developer,
        variables: { path: project.full_path, iid: merge_request.iid.to_s })

      second_page = graphql_data_at(*diffs_path, :nodes).map { |node| node['newPath'] }

      expect(second_page).to be_present
      expect(second_page).not_to match_array(first_page)
    end
  end

  context 'with a path' do
    let(:diff_args) { '(path: "files/ruby/popen.rb")' }

    it 'finds a file beyond the first page without pagination', :aggregate_failures do
      post_graphql(query.sub(diff_args, '(first: 1)'), current_user: developer,
        variables: { path: project.full_path, iid: merge_request.iid.to_s })

      expect(graphql_data_at(*diffs_path, :nodes)).to contain_exactly(
        include('newPath' => 'bar/branch-test.txt')
      )

      run_query(developer)

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(*diffs_path, :nodes)).to contain_exactly(
        include('newPath' => 'files/ruby/popen.rb', 'diff' => include('@@'))
      )
      expect(graphql_data_at(*diffs_path, :pageInfo)).to eq(
        'hasNextPage' => false, 'endCursor' => nil, 'hasPreviousPage' => false, 'startCursor' => nil
      )
      expect(graphql_data_at(*diffs_path, :overflow)).to be(false)
    end

    context 'when the diff files were cleaned' do
      before do
        merge_request_diff = MergeRequestDiff.find(merge_request.merge_request_diff.id)
        merge_request_diff.clean!
        # Association delete_all nullifies the partition key on merge_request_diff_files.
        MergeRequestDiffFile.where(merge_request_diff_id: merge_request_diff.id).delete_all
      end

      it 'loads the matching patch from the repository' do
        run_query(developer)

        expect(graphql_data_at(*diffs_path, :nodes)).to contain_exactly(
          include('newPath' => 'files/ruby/popen.rb', 'diff' => include('@@'))
        )
      end

      context 'with a directory path' do
        let(:diff_args) { '(path: "files/ruby")' }

        it 'returns no nodes and does not load that pathspec' do
          expect_next_instance_of(Compare) do |comparison|
            expect(comparison).not_to receive(:diffs)
          end

          run_query(developer)

          expect(graphql_data_at(*diffs_path, :nodes)).to be_empty
        end
      end

      context 'with a glob path' do
        let(:diff_args) { '(path: "*.rb")' }

        it 'returns no nodes and does not load that pathspec' do
          expect_next_instance_of(Compare) do |comparison|
            expect(comparison).not_to receive(:diffs)
          end

          run_query(developer)

          expect(graphql_data_at(*diffs_path, :nodes)).to be_empty
        end
      end

      context 'when the cleaned diff starts at the blank ref' do
        let(:diff_args) { '(path: "bar/branch-test.txt")' }

        before do
          MergeRequestDiff.find(merge_request.merge_request_diff.id)
            .update!(start_commit_sha: Gitlab::Git::SHA1_BLANK_SHA)
        end

        it 'returns the file and no GraphQL error' do
          run_query(developer)

          expect(graphql_errors).to be_nil
          expect(graphql_data_at(*diffs_path, :nodes)).to contain_exactly(
            include('newPath' => 'bar/branch-test.txt')
          )
        end
      end

      context 'with a renamed file' do
        using RSpec::Parameterized::TableSyntax

        where(:path) { ['files/js/commit.js.coffee', 'files/js/commit.coffee'] }

        with_them do
          let(:diff_args) { %[(path: "#{path}")] }

          it 'returns the rename from the repository for either path' do
            run_query(developer)

            expect(graphql_data_at(*diffs_path, :nodes)).to contain_exactly(
              include(
                'oldPath' => 'files/js/commit.js.coffee',
                'newPath' => 'files/js/commit.coffee',
                'renamedFile' => 'true',
                'deletedFile' => 'false',
                'newFile' => 'false',
                'diff' => include('@@ -1,6 +1,6 @@')
              )
            )
          end
        end
      end
    end

    context 'with a renamed file' do
      using RSpec::Parameterized::TableSyntax

      where(:path) { ['files/js/commit.js.coffee', 'files/js/commit.coffee'] }

      with_them do
        let(:diff_args) { %[(path: "#{path}")] }

        it 'matches either the old or new path' do
          run_query(developer)

          expect(graphql_data_at(*diffs_path, :nodes)).to contain_exactly(
            include('oldPath' => 'files/js/commit.js.coffee', 'newPath' => 'files/js/commit.coffee',
              'renamedFile' => 'true')
          )
        end
      end
    end

    context 'when first is combined with path' do
      let(:diff_args) { '(path: "files/ruby/popen.rb", first: 0)' }

      it 'returns an argument error' do
        run_query(developer)

        expect_graphql_errors_to_include('The path argument cannot be combined with first')
      end
    end

    context 'when expanded is set on a generated path' do
      let(:diff_args) { '(path: "generated.txt", expanded: false)' }
      let(:generated_project) do
        create(:project, :private, :custom_repo, files: {
          '.gitattributes' => "generated.txt gitlab-generated\n"
        })
      end

      let(:generated_merge_request) do
        create(:merge_request,
          source_project: generated_project,
          target_project: generated_project,
          source_branch: 'generated-branch',
          target_branch: generated_project.default_branch)
      end

      before do
        generated_project.repository.create_branch('generated-branch', generated_project.default_branch)
        generated_project.repository.create_file(
          generated_project.creator,
          'generated.txt',
          "alpha\n",
          message: 'Add generated file',
          branch_name: 'generated-branch'
        )
      end

      def run_generated_query(expanded:)
        post_graphql(
          query.sub('expanded: false', "expanded: #{expanded}"),
          current_user: generated_project.creator,
          variables: { path: generated_project.full_path, iid: generated_merge_request.iid.to_s }
        )
      end

      it 'returns patch text only when expansion is requested', :aggregate_failures do
        run_generated_query(expanded: false)

        expect(graphql_data_at(*diffs_path, :nodes)).to contain_exactly(
          include('newPath' => 'generated.txt', 'collapsed' => 'true', 'diff' => '')
        )

        run_generated_query(expanded: true)

        expect(graphql_data_at(*diffs_path, :nodes)).to contain_exactly(
          include('newPath' => 'generated.txt', 'collapsed' => 'false', 'diff' => include('@@'))
        )
      end
    end

    context 'when the stored diff hit the file limit' do
      before do
        stub_application_setting(diff_max_files: 5)
        merge_request.create_merge_request_diff
      end

      context 'with a path that was not stored' do
        let(:diff_args) { '(path: "README")' }

        it 'reports overflow', :aggregate_failures do
          run_query(developer)

          expect(graphql_data_at(*diffs_path, :nodes)).to be_empty
          expect(graphql_data_at(*diffs_path, :overflow)).to be(true)
        end
      end

      context 'with a path that was stored' do
        let(:diff_args) { '(path: "CHANGELOG")' }

        it 'returns the file without overflow', :aggregate_failures do
          run_query(developer)

          expect(graphql_data_at(*diffs_path, :nodes)).to contain_exactly(include('newPath' => 'CHANGELOG'))
          expect(graphql_data_at(*diffs_path, :overflow)).to be(false)
        end
      end
    end

    context 'with an unknown path' do
      let(:diff_args) { '(path: "not-in-the-diff.txt")' }

      it 'returns an empty connection without overflow', :aggregate_failures do
        run_query(developer)

        expect(graphql_data_at(*diffs_path, :nodes)).to be_empty
        expect(graphql_data_at(*diffs_path, :overflow)).to be(false)
      end
    end

    context 'when the current user cannot read the merge request' do
      let_it_be(:outsider) { create(:user) }

      it 'hides the private project and returns no GraphQL error' do
        run_query(outsider)

        expect(graphql_errors).to be_nil
        expect(graphql_data).to eq('project' => nil)
      end
    end
  end

  context 'with the expanded argument' do
    let(:diff_args) { '(expanded: true)' }

    it 'accepts the argument and returns per-file diffs', :aggregate_failures do
      run_query(developer)

      nodes = graphql_data_at(*diffs_path, :nodes)

      expect(graphql_errors).to be_nil
      expect(nodes).to be_present
      expect(graphql_data_at(*diffs_path, :overflow)).to be(false)
    end
  end

  context 'when a page overflows the diff size limits' do
    let(:diff_args) { '(expanded: true)' }

    before do
      stub_application_setting(diff_max_lines: 150, diff_max_files: 1000)
    end

    it 'reports overflow on the connection' do
      run_query(developer)

      expect(graphql_data_at(*diffs_path, :overflow)).to be(true)
    end
  end

  context 'when the current user cannot read the merge request' do
    let_it_be(:outsider) { create(:user) }

    it 'does not expose the merge request or its diffs' do
      run_query(outsider)

      expect(graphql_data_at(:project, :mergeRequest)).to be_nil
    end
  end

  describe 'granular PAT authorization' do
    let(:user) { developer }
    let(:boundary_object) { project }
    let(:request) do
      post_graphql(query, token: { personal_access_token: pat },
        variables: { path: project.full_path, iid: merge_request.iid.to_s })
    end

    def merge_request_query(fields)
      <<~GQL
        query($path: ID!, $iid: String!) {
          project(fullPath: $path) {
            mergeRequest(iid: $iid) {
              #{fields}
            }
          }
        }
      GQL
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      [:read_project, :read_merge_request] do
      let(:skipped_data_path) { [*diffs_path, :nodes, :new_path] }
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      [:read_project, :read_merge_request] do
      let(:diff_args) { '(path: "files/ruby/popen.rb")' }
      let(:skipped_data_path) { [*diffs_path, :nodes, :new_path] }
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      [:read_project, :read_merge_request] do
      let(:query) { merge_request_query('diffStats { path additions deletions }') }
      let(:skipped_data_path) { %i[project mergeRequest diffStats] }
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      [:read_project, :read_merge_request] do
      let(:query) { merge_request_query('diffStatsSummary { fileCount additions deletions changes }') }
      let(:skipped_data_path) { %i[project mergeRequest diffStatsSummary] }
    end
  end
end
