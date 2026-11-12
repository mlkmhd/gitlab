# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'admin/gitlab_credits_dashboard/users/show.html.haml', feature_category: :consumables_cost_management do
  let(:selector) { '#js-instance-user-usage-billing-dashboard' }
  let(:element) { Nokogiri::HTML(rendered).at_css(selector) }

  before do
    assign(:username, 'jdoe')
  end

  it 'renders the dashboard root element with the username' do
    render

    expect(rendered).to have_selector(selector)
    expect(element['data-username']).to eq('jdoe')
  end

  context 'when there is a billable license' do
    let(:license) { build(:license, starts_at: Date.new(2026, 3, 1)) }

    before do
      allow(License).to receive(:billable_license).and_return(license)
    end

    it 'renders the subscription start date' do
      render

      expect(rendered).to have_selector(selector)
      expect(element['data-subscription-start-date']).to eq('2026-03-01')
    end
  end

  context 'when there is no billable license' do
    before do
      allow(License).to receive(:billable_license).and_return(nil)
    end

    it 'does not render a subscription start date' do
      render

      expect(rendered).to have_selector(selector)
      expect(element['data-subscription-start-date']).to be_nil
    end
  end
end
