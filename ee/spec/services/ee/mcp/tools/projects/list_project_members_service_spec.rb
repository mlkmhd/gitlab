# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Projects::ListProjectMembersService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :public) }
  let_it_be(:subgroup) { create(:group, :public, parent: group) }
  let_it_be(:member_project) { create(:project, :public, group: subgroup, maintainers: [user]) }

  let(:service) { described_class.new(name: 'list_project_members') }

  before do
    service.set_cred(current_user: user)
  end

  describe '#execute' do
    # Each new inherited source group adds a SAML provider lookup.
    # TODO: https://gitlab.com/gitlab-org/gitlab/-/work_items/637152
    it_behaves_like 'an MCP tool that avoids N+1 queries', threshold: 1 do
      let(:arguments) { { project_id: member_project.full_path, include_inherited: true } }

      before_all do
        subgroup.add_developer(create(:user))
      end

      def create_additional_records
        member_project.add_developer(create(:user))
        group.add_developer(create(:user))
      end
    end
  end
end
