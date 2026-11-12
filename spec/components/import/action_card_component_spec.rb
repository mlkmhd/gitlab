# frozen_string_literal: true

require "spec_helper"

RSpec.describe Import::ActionCardComponent, feature_category: :importers do
  let(:href) { '/import/github/new' }
  let(:link_options) { {} }

  before do
    render_inline described_class.new(
      title: 'GitHub',
      description: 'Repositories, issues, and pull requests',
      icon: 'github',
      href: href,
      link_options: link_options
    )
  end

  it 'renders the whole card as one link with the icon, title, description and arrow', :aggregate_failures do
    card = page.find("a[href='#{href}']")

    expect(card).to have_css("svg[data-testid='github-icon']")
    expect(card).to have_css('span.gl-font-bold', text: 'GitHub')
    expect(card).to have_text('Repositories, issues, and pull requests')
    expect(card).to have_css("svg[data-testid='arrow-right-icon']")
  end

  it 'uses the subtle background and default border' do
    expect(page).to have_css('a.gl-bg-subtle.gl-border-default')
  end

  it 'hides the icons from assistive technology', :aggregate_failures do
    expect(page).to have_css("[aria-hidden='true'] svg[data-testid='arrow-right-icon']")
    expect(page).to have_css("[aria-hidden='true'] svg[data-testid='github-icon']")
  end

  context 'with link options' do
    let(:link_options) { { class: 'js-import-github', data: { testid: 'github-import-button', platform: 'github' } } }

    it 'merges the extra class with the card classes and keeps the data attributes' do
      expect(page).to have_css(
        "a.js-import-github.gl-flex[href='#{href}'][data-testid='github-import-button'][data-platform='github']"
      )
    end
  end
end
