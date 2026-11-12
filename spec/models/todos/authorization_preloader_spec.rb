# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Todos::AuthorizationPreloader, feature_category: :notifications do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, developers: user) }
  let_it_be(:todo_ids) do
    [
      create(:todo, user: user, project: project, target: create(:issue, project: project)),
      create(:todo, user: user, project: project,
        target: create(:merge_request, :skip_diff_creation, source_project: project)),
      create(:on_commit_todo, user: user, project: project),
      create(:todo, :member_access_requested, user: user, project: nil, group: group, target: group)
    ].map(&:id)
  end

  let(:todos) { Todo.id_in(todo_ids).with_entity_associations.to_a }

  describe '#execute' do
    it 'preloads the organization of each target project when targets share a project' do
      described_class.new(todos, user).execute

      issue = todos.map(&:target).find { |target| target.is_a?(Issue) }
      merge_request = todos.map(&:target).find { |target| target.is_a?(MergeRequest) }

      expect([issue.project, merge_request.target_project].map { |p| p.association(:organization).loaded? })
        .to all(be(true))
    end

    it 'skips targets without a project association' do
      expect { described_class.new(todos, user).execute }.not_to raise_error
      expect(todos.map(&:target)).to include(group)
    end
  end
end
