# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Groups::ListGroupsService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:parent) { create(:group, :public) }

  let(:service) { described_class.new(name: 'list_groups') }

  before do
    service.set_cred(current_user: user)
  end

  describe '#execute' do
    # The 8 extra queries are root-ancestor and group SAML policy lookups,
    # which should drop to 0 once this issue is fixed.
    # TODO: https://gitlab.com/gitlab-org/gitlab/-/work_items/637152
    it_behaves_like 'an MCP tool that avoids N+1 queries', threshold: 8 do
      let(:arguments) { { group_id: parent.full_path, include_subgroups: true } }

      before_all do
        create(:group, :public, parent: parent)
      end

      def create_additional_records
        2.times do
          intermediate = create(:group, :public, parent: parent)
          create(:group, :public, parent: intermediate)
        end
      end
    end
  end
end
