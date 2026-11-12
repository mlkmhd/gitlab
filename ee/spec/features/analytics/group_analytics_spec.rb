# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GroupAnalytics', feature_category: :devops_reports do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }

  before do
    stub_licensed_features(group_activity_analytics: true)

    group.add_developer(user)
    sign_in(user)
  end

  it 'does not render the container on the top-level group overview' do
    visit group_path(group)

    expect(page).to have_css('[data-testid="group-page-sidebar"]')
    expect(page).not_to have_css('#js-group-activity')
  end

  it 'renders the container on the subgroup overview' do
    visit group_path(subgroup)

    expect(page).to have_css('#js-group-activity')
  end

  context 'when group_overview_sidebar feature flag is disabled' do
    before do
      stub_feature_flags(group_overview_sidebar: false)
    end

    it 'renders the container on the top-level group overview' do
      visit group_path(group)

      expect(page).to have_css('#js-group-activity')
    end
  end
end
