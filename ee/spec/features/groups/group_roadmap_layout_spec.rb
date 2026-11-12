# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'group epic roadmap layout', :js, feature_category: :portfolio_management do
  include FilteredSearchHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :public) }
  let_it_be(:bug_label) { create(:group_label, group: group, title: 'Bug') }
  let_it_be(:end_of_quarter) { Time.zone.today.end_of_quarter }

  let_it_be(:epic) do
    create(:labeled_epic, group: group, start_date: end_of_quarter - 10.days, end_date: end_of_quarter - 1.day,
      labels: [bug_label])
  end

  let_it_be(:epic_without_label) do
    create(:epic, group: group, start_date: end_of_quarter - 10.days, end_date: end_of_quarter - 1.day)
  end

  # Reads overlap and scroll positions in one call so both describe the same moment.
  def layout_state
    page.evaluate_script(<<~JS)
      (() => ({
        overlaps:
          document.querySelector('.epics-filters').getBoundingClientRect().top <
          document.querySelector('.panel-header').getBoundingClientRect().bottom,
        scrollTops: ['.panel-content-inner', '.group-epics-roadmap', '.roadmap-container'].map(
          (selector) => document.querySelector(selector).scrollTop
        )
      }))()
    JS
  end

  # `scrollToCurrentDay` runs a couple of ticks after mount, so wait for the indicator before reading.
  def wait_for_roadmap_to_settle
    expect(page).to have_css('.roadmap-container .epics-list-item .epic-title')
    expect(page).to have_css('.epics-filters')
    expect(page).to have_css('.js-current-day-indicator[style*="left"]', minimum: 1, visible: :all)
  end

  def wait_for_milestones(count)
    expect(page).to have_css('.roadmap-container .milestones-list-section .milestone-item-details', count: count)
  end

  def filter_by_label
    page.within('.vue-filtered-search-bar-container .gl-search-box-by-click') do
      find_by_testid('filtered-search-term-input').click
      click_button 'Label'
      page.first('.gl-filtered-search-suggestion-list .gl-filtered-search-suggestion').click
      page.find('.gl-filtered-search-suggestion-list .gl-filtered-search-suggestion', text: bug_label.title).click
    end
    page.find('.gl-search-box-by-click-search-button').click

    expect(page).to have_css('.roadmap-container .epics-list-item .epic-title', count: 1)
    expect_vue_tokens([label_token(bug_label.title)])
  end

  def expect_toolbar_visible_and_unscrolled
    state = layout_state

    expect(state['overlaps']).to be(false)
    expect(state['scrollTops']).to eq([0, 0, 0])
  end

  before do
    stub_licensed_features(epics: true)

    sign_in(user)
    page.current_window.resize_to(1200, 800)
    visit group_roadmap_path(group)
  end

  it 'does not cover the toolbar with the panel header' do
    wait_for_roadmap_to_settle

    expect(layout_state['overlaps']).to be(false)
  end

  it 'does not cover the toolbar after filtering' do
    wait_for_roadmap_to_settle

    filter_by_label

    expect(layout_state['overlaps']).to be(false)
  end

  context 'with milestones taller than the viewport' do
    let_it_be(:milestones) do
      # 30 rows of 32px exceed the 800px viewport
      create_list(:milestone, 30, :with_dates, group: group, # rubocop:disable FactoryBot/ExcessiveCreateList -- list must be taller than the viewport
        start_date: end_of_quarter - 10.days, due_date: end_of_quarter - 1.day)
    end

    it 'keeps the toolbar visible and does not scroll the page on load' do
      wait_for_roadmap_to_settle
      wait_for_milestones(30)

      expect_toolbar_visible_and_unscrolled
    end

    it 'keeps the toolbar visible and does not scroll the page after filtering' do
      wait_for_roadmap_to_settle
      wait_for_milestones(30)

      filter_by_label

      wait_for_roadmap_to_settle
      wait_for_milestones(30)
      expect_toolbar_visible_and_unscrolled
    end
  end
end
