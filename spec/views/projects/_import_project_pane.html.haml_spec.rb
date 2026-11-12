# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'projects/_import_project_pane', feature_category: :importers do
  let(:importers) do
    %i[
      github_import_enabled? bitbucket_import_enabled? git_import_enabled? bitbucket_server_import_enabled?
      gitea_import_enabled? fogbugz_import_enabled? gitlab_project_import_enabled? manifest_import_enabled?
    ]
  end

  let(:card_selectors) do
    {
      github_import_enabled?: ".js-import-github[data-platform='github']",
      bitbucket_import_enabled?: ".import_bitbucket[data-platform='bitbucket_cloud']",
      git_import_enabled?: "[data-testid='new-project-import-url-button'][data-platform='repo_url']",
      bitbucket_server_import_enabled?: ".import_bitbucket[data-platform='bitbucket_server']",
      gitea_import_enabled?: ".import_gitea[data-platform='gitea']",
      fogbugz_import_enabled?: ".import_fogbugz[data-platform='fogbugz']",
      gitlab_project_import_enabled?: ".js-import-gitlab-project-btn[data-platform='gitlab_export']",
      manifest_import_enabled?: ".import_manifest[data-platform='manifest_file']"
    }
  end

  let(:disabled_importers) { [] }
  let(:bitbucket_import_configured) { false }

  before do
    allow(view).to receive_messages(
      current_user: build_stubbed(:user),
      bitbucket_import_configured?: bitbucket_import_configured,
      **importers.index_with { |importer| disabled_importers.exclude?(importer) }
    )

    render 'projects/import_project_pane', destination_namespace_id: 1
  end

  def card(selector = '')
    "a.js-import-project-btn.gl-bg-subtle#{selector}"
  end

  # Only the known importer cards, so extra partials (such as JH's Gitee link) don't change the counts.
  def known_cards(suffix = '', parent: '')
    card_selectors.values.map { |selector| "#{parent}#{card(selector)}#{suffix}" }.join(', ')
  end

  it 'renders every enabled importer as a card that keeps its JS hooks and data', :aggregate_failures do
    expect(rendered).to have_css(card(
      ".import_bitbucket.js-how-to-import-link[data-modal-title='#{_('Import projects from Bitbucket')}']" \
        "[data-platform='bitbucket_cloud']"
    ))
    expect(rendered).to have_css(card(
      ".js-import-gitlab-project-btn[href='#'][data-href='#{new_import_gitlab_project_path}']" \
        "[data-testid='gitlab-import-button']"
    ))
    card_selectors.each_value { |selector| expect(rendered).to have_css(card(selector)) }
    expect(rendered).to have_css(known_cards("[data-track-action='click_button'][data-track-label='import_project']"),
      count: 8)
  end

  it 'links every source card to its importer with the destination namespace', :aggregate_failures do
    {
      github_import_enabled?: new_import_github_path(namespace_id: 1),
      bitbucket_import_enabled?: status_import_bitbucket_path(namespace_id: 1),
      git_import_enabled?: new_import_url_path(namespace_id: 1),
      bitbucket_server_import_enabled?: status_import_bitbucket_server_path(namespace_id: 1),
      gitea_import_enabled?: new_import_gitea_path(namespace_id: 1),
      fogbugz_import_enabled?: new_import_fogbugz_path(namespace_id: 1),
      manifest_import_enabled?: new_import_manifest_path(namespace_id: 1)
    }.each do |importer, path|
      expect(path).to include('namespace_id=1')
      expect(rendered).to have_css(card("#{card_selectors[importer]}[href='#{path}']"))
    end
  end

  it 'passes the OAuth setup message to the Bitbucket Cloud modal' do
    bitbucket_card = Capybara.string(rendered).find(card(card_selectors[:bitbucket_import_enabled?]))

    expect(bitbucket_card['data-modal-message']).to eq(view.import_from_bitbucket_message)
  end

  context 'when Bitbucket Cloud import is configured' do
    let(:bitbucket_import_configured) { true }

    it 'links straight to the Bitbucket import status page', :aggregate_failures do
      path = status_import_bitbucket_path(namespace_id: 1)

      expect(rendered).to have_css(card("#{card_selectors[:bitbucket_import_enabled?]}[href='#{path}']"))
      expect(rendered).not_to have_css('.js-how-to-import-link')
    end
  end

  it 'renders the cards in a responsive grid' do
    expect(rendered).to have_css(known_cards(parent: '.gl-grid.gl-grid-cols-1.gl-gap-6 > '), count: 8)
  end

  it 'links History to the import history page' do
    expect(rendered).to have_link(_('History'), href: import_history_index_path)
  end

  it 'renders the section heading for screen readers only' do
    expect(rendered).to have_css('h5.gl-sr-only', text: _('Import project from'), visible: :all)
  end

  it 'renders the direct transfer line with its docs link', :aggregate_failures do
    expect(rendered).to have_css("svg[data-testid='bulb-icon']")
    message = s_('ImportProjects|Moving projects between GitLab instances? %{link_start}Direct transfer%{link_end} ' \
      'is recommended, and moves whole groups at once.')

    expect(rendered).to have_text(format(message, link_start: '', link_end: ''))
    expect(rendered).to have_link(message[/%{link_start}(.+)%{link_end}/, 1],
      href: help_page_path('user/group/import/_index.md'))
    expect(rendered).not_to have_css('.gl-alert')
  end

  context 'when an importer is disabled' do
    where(importer: %i[
      github_import_enabled? bitbucket_import_enabled? git_import_enabled? bitbucket_server_import_enabled?
      gitea_import_enabled? fogbugz_import_enabled? gitlab_project_import_enabled? manifest_import_enabled?
    ])

    with_them do
      let(:disabled_importers) { [importer] }

      it 'does not render its card and keeps the others', :aggregate_failures do
        expect(rendered).not_to have_css(card(card_selectors[importer]))
        card_selectors.except(importer).each_value { |selector| expect(rendered).to have_css(card(selector)) }
        expect(rendered).to have_css(known_cards, count: 7)
      end
    end
  end
end
