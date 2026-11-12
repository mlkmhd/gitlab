# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.project(fullPath).pathLocks', feature_category: :source_code_management do
  using RSpec::Parameterized::TableSyntax
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, namespace: user.namespace) }
  let_it_be(:path_lock) { create(:path_lock, project: project, path: 'README.md') }

  let(:path_locks_args) { {} }

  subject(:path_locks_response) do
    post_graphql(
      graphql_query_for(
        :project, { full_path: project.full_path },
        query_graphql_field(:path_locks, path_locks_args, "nodes { #{all_graphql_fields_for('PathLock')} }")
      ),
      current_user: user
    )

    graphql_data_at(:project, :pathLocks, :nodes)
  end

  context 'unlicensed feature' do
    before do
      stub_licensed_features(file_locks: false)
    end

    it { is_expected.to be_empty }
  end

  context 'licensed feature' do
    before do
      stub_licensed_features(file_locks: true)
    end

    it 'returns path locks' do
      is_expected.to match_array(
        a_hash_including('id' => path_lock.to_global_id.to_s, 'path' => 'README.md')
      )
    end

    context 'with the path argument' do
      let_it_be(:directory_lock) { create(:path_lock, project: project, path: 'app/models') }

      let(:path_locks_args) { { path: 'app/models/user.rb' } }

      it 'returns only locks related to the path' do
        is_expected.to match_array(a_hash_including('path' => 'app/models'))
      end

      context 'when another project of the user has a lock on the same path' do
        before_all do
          create(:path_lock, project: create(:project, namespace: user.namespace), path: 'app/models')
        end

        it 'returns only locks from the project' do
          is_expected.to match_array(a_hash_including('id' => directory_lock.to_global_id.to_s))
        end
      end

      context 'when the path is longer than 4096 characters' do
        let(:path_locks_args) { { path: 'a' * 4097 } }

        it 'returns an error' do
          path_locks_response

          expect_graphql_errors_to_include('path is too long (maximum is 4096)')
        end
      end

      context 'when the path is empty' do
        let(:path_locks_args) { { path: '' } }

        it 'returns all path locks' do
          is_expected.to match_array([
            a_hash_including('path' => 'README.md'),
            a_hash_including('path' => 'app/models')
          ])
        end
      end

      context 'when the project has more locks than the page size' do
        before_all do
          create_list(:path_lock, 2, project: project)
        end

        before do
          allow(GitlabSchema).to receive(:default_max_page_size).and_return(2)
        end

        it 'still returns the related lock' do
          is_expected.to match_array(a_hash_including('path' => 'app/models'))
        end
      end
    end
  end
end
