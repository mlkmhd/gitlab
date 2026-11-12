# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/FactoryBot/AvoidCreate -- permission checks need persisted records
RSpec.describe 'groups/_sidebar', feature_category: :groups_and_projects do
  let_it_be(:owner) { create(:user) }
  let_it_be(:developer) { create(:user) }
  let_it_be(:group) { create(:group, owners: owner, developers: developer, description: 'Our **core** products') }

  let(:current_user) { owner }

  before do
    allow(view).to receive(:current_user).and_return(current_user)

    render 'groups/sidebar', group: group
  end

  it 'renders the group information heading and description' do
    expect(rendered).to have_css('h2', text: s_('GroupPage|Group information'))
    expect(rendered).to have_css('.read-more-container[data-read-more-height="320"] .read-more-content strong',
      text: 'core')
    expect(rendered).to have_button(_('Read more'))
  end

  context 'when the group has no description' do
    let_it_be(:group) { create(:group, owners: owner) }

    it 'renders the heading without a description' do
      expect(rendered).to have_css('h2', text: s_('GroupPage|Group information'))
      expect(rendered).not_to have_css('.read-more-container')
    end
  end

  describe 'members link' do
    it 'links to the group members page without a count' do
      expect(rendered).to have_link(_('Members'), href: group_group_members_path(group), exact: true)
    end

    it 'tracks clicks' do
      expect(rendered).to trigger_internal_events('click_members_link_on_group_overview').on_click
    end

    context 'when the user cannot read group members' do
      let_it_be(:group) { create(:group, :private) }
      let_it_be(:project_developer) { create(:user) }

      let(:current_user) { project_developer }

      before_all do
        create(:project, group: group, developers: project_developer)
      end

      it 'does not render the members link' do
        expect(rendered).not_to have_link(href: group_group_members_path(group))
      end
    end
  end

  describe 'invite members' do
    it 'renders the invite members trigger' do
      expect(rendered).to have_css('.js-invite-members-trigger[data-trigger-source="group_overview"]')
    end

    it 'tracks clicks' do
      expect(rendered).to trigger_internal_events('click_invite_members_on_group_overview').on_click
    end

    context 'when the user cannot invite members' do
      let(:current_user) { developer }

      it 'does not render the invite members trigger' do
        expect(rendered).not_to have_css('.js-invite-members-trigger')
        expect(rendered).to have_link(href: group_group_members_path(group))
      end
    end
  end
end
# rubocop:enable RSpec/FactoryBot/AvoidCreate
