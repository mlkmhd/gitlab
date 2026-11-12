# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'groups/settings/gitlab_credits_dashboard/users/show.html.haml', feature_category: :consumables_cost_management do
  let(:group) { build_stubbed(:group) }
  let(:selector) { '#js-group-user-usage-billing-dashboard' }
  let(:element) { Nokogiri::HTML(rendered).at_css(selector) }

  before do
    assign(:group, group)
    assign(:username, 'jdoe')
  end

  it 'renders the dashboard root element with the username and namespace path' do
    render

    expect(rendered).to have_selector(selector)
    expect(element['data-username']).to eq('jdoe')
    expect(element['data-namespace-path']).to eq(group.full_path)
  end

  context 'when the group has a subscription' do
    before do
      build_stubbed(:gitlab_subscription, namespace: group, start_date: Date.new(2026, 3, 1))
    end

    it 'renders the subscription start date' do
      render

      expect(rendered).to have_selector(selector)
      expect(element['data-subscription-start-date']).to eq('2026-03-01')
    end
  end

  context 'when the group has no subscription' do
    it 'does not render a subscription start date' do
      render

      expect(rendered).to have_selector(selector)
      expect(element['data-subscription-start-date']).to be_nil
    end
  end
end
