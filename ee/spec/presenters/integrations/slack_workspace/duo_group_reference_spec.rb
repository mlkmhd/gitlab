# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackWorkspace::DuoGroupReference, feature_category: :integrations do
  let(:group) { build_stubbed(:group) }
  let(:current_user) { build_stubbed(:user) }
  let(:can_read) { true }
  let(:can_update) { false }

  subject(:reference) { described_class.for(group, current_user) }

  before do
    next unless current_user

    allow(Ability).to receive(:allowed?).with(current_user, :read_group, group).and_return(can_read)
    allow(Ability).to receive(:allowed?).with(current_user, :update_duo_in_slack, group).and_return(can_update)
  end

  context 'for someone who can change GitLab Duo in Slack' do
    let(:can_update) { true }

    it "links to the group's GitLab for Slack page" do
      expect(reference).to eq(id: group.id, name: group.full_name, link_kind: :settings,
        link_path: Gitlab::Routing.url_helpers.edit_group_settings_integration_path(group, :gitlab_slack_application))
    end
  end

  context 'for someone who can only see the group' do
    it 'links to the Owners of the group' do
      expect(reference).to include(id: group.id, name: group.full_name, link_kind: :owners)
      expect(reference[:link_path]).to include("max_role=static-#{Gitlab::Access::OWNER}")
    end
  end

  context 'for someone who cannot see the group' do
    let(:can_read) { false }

    it { is_expected.to be_nil }
  end

  context 'without a group' do
    let(:group) { nil }

    it { is_expected.to be_nil }
  end

  context 'without a current user' do
    let(:current_user) { nil }

    it { is_expected.to be_nil }
  end
end
