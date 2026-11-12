# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::MergeRequests::ResolveConflicts, feature_category: :code_review_workflow do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }

  # Private: a non-member author of a public project's merge request may update it,
  # which the permission shared example does not expect
  let_it_be(:project) { create(:project, :repository) }

  let(:merge_request) do
    create(:merge_request, source_project: project, source_branch: 'conflict-resolvable',
      target_branch: 'conflict-start', merge_status: :cannot_be_merged)
  end

  let(:files) do
    [
      {
        our_path: 'files/ruby/popen.rb',
        their_path: 'files/ruby/old_popen.rb',
        sections: [{ section_id: 'popen_section', resolution: 'head' }]
      },
      { our_path: 'files/ruby/regex.rb', their_path: 'files/ruby/regex.rb', content: "resolved\n" }
    ]
  end

  let(:query) { GraphQL::Query.new(empty_schema, document: nil, context: {}, variables: {}) }
  let(:context) { GraphQL::Query::Context.new(query: query, values: { current_user: user }) }

  subject(:mutation) { described_class.new(object: nil, context: context, field: nil) }

  specify { expect(described_class).to require_graphql_authorizations(:update_merge_request) }

  describe '#resolve' do
    subject(:resolve) do
      mutation.resolve(project_path: project.full_path, iid: merge_request.iid, files: files, commit_message: 'Resolve')
    end

    it_behaves_like 'permission level for merge request mutation is correctly verified'

    context 'when the user can update the merge request' do
      before_all do
        project.add_developer(user)
      end

      it 'passes the files to the service in the shape the web UI posts' do
        expect_next_instance_of(::MergeRequests::Conflicts::ResolveService, merge_request) do |service|
          expect(service).to receive(:execute).with(
            user,
            {
              commit_message: 'Resolve',
              files: [
                {
                  old_path: 'files/ruby/old_popen.rb',
                  new_path: 'files/ruby/popen.rb',
                  sections: { 'popen_section' => 'head' }
                },
                { old_path: 'files/ruby/regex.rb', new_path: 'files/ruby/regex.rb', content: "resolved\n" }
              ]
            }
          ).and_return(ServiceResponse.success)
        end

        expect(resolve).to eq(merge_request: merge_request, errors: [])
      end

      it 'returns the error of the service' do
        expect_next_instance_of(::MergeRequests::Conflicts::ResolveService) do |service|
          expect(service).to receive(:execute).and_return(ServiceResponse.error(message: 'Refused'))
        end

        expect(resolve).to eq(merge_request: merge_request, errors: ['Refused'])
      end
    end
  end
end
