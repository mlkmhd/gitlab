# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::MilestonesController, feature_category: :team_planning do
  describe 'DELETE #destroy' do
    let_it_be(:project) { create(:project) }
    let_it_be(:user) { create(:user, maintainer_of: project) }
    let_it_be(:other_maintainer) { create(:user, maintainer_of: project) }

    let(:current_user) { user }

    before do
      stub_const('Milestones::DestroyService::RATE_LIMITED_ISSUABLES_THRESHOLD', 0)
    end

    def delete_milestone_as(requesting_user)
      login_as(requesting_user)
      milestone = create(:milestone, project: project)
      create(:issue, project: project, milestone: milestone)

      delete project_milestone_path(project, milestone)
    end

    it_behaves_like 'rate limited endpoint', rate_limit_key: :milestone_destroy do
      def request
        delete_milestone_as(user)
      end

      def request_with_second_scope
        delete_milestone_as(other_maintainer)
      end
    end
  end
end
