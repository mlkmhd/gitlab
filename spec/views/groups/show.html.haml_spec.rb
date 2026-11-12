# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'groups/show', feature_category: :groups_and_projects do
  describe 'group overview sidebar' do
    let_it_be(:group) { create(:group, description: 'Our core products') } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- real organization association is required here
    let_it_be(:subgroup) { create(:group, parent: group, description: 'Subgroup products') } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- real organization association is required here

    it 'renders the group information sidebar for a top-level group' do
      assign(:group, group)

      render

      expect(rendered).to have_css('[data-testid="detail-layout-sidebar"] [data-testid="group-page-sidebar"]',
        text: 'Our core products')
      expect(rendered).to have_css('[data-testid="detail-layout-content"] #js-groups-show-app')
      expect(rendered).to have_css('h1', text: group.name)
      expect(rendered).not_to have_css('.group-home-panel')
    end

    it 'renders the home panel for a subgroup' do
      assign(:group, subgroup)

      render

      expect(rendered).to have_css('.group-home-panel .home-panel-description', text: 'Subgroup products')
      expect(rendered).not_to have_css('[data-testid="group-page-sidebar"]')
    end

    context 'when group_overview_sidebar feature flag is disabled' do
      before do
        stub_feature_flags(group_overview_sidebar: false)
      end

      it 'renders the home panel for a top-level group' do
        assign(:group, group)

        render

        expect(rendered).to have_css('.group-home-panel .home-panel-description', text: 'Our core products')
        expect(rendered).not_to have_css('[data-testid="group-page-sidebar"]')
      end
    end
  end

  describe 'group README' do
    let_it_be(:group) { create(:group) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- real organization association is required here
    let_it_be(:readme_project) { build_stubbed(:project, :public, :readme) }

    before do
      assign(:group, group)
    end

    context 'with readme project' do
      before do
        allow(group).to receive_messages(group_readme: readme_project, readme_project: readme_project)
      end

      it 'renders #js-group-readme' do
        render

        expect(rendered).to have_selector('#js-group-readme')
      end

      context 'with private readme project' do
        let_it_be(:readme_project) { build_stubbed(:project, :private, :readme) }

        it 'does not render #js-group-readme' do
          render

          expect(rendered).not_to have_selector('#js-group-readme')
        end
      end
    end

    context 'without readme project' do
      before do
        allow(group).to receive(:readme_project).and_return(nil)
      end

      it 'does not render #js-group-readme' do
        render

        expect(rendered).not_to have_selector('#js-group-readme')
      end
    end
  end
end
