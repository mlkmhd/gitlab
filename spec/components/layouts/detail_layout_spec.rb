# frozen_string_literal: true

require "spec_helper"

RSpec.describe Layouts::DetailLayout, feature_category: :design_system do
  let(:heading) { 'Page heading' }
  let(:sidebar) { 'Sidebar' }
  let(:content) { 'Default content' }

  it_behaves_like 'a base layout component'

  describe 'loading skeleton' do
    let(:skeleton_region) { ->(region) { "[data-testid=\"detail-layout-skeleton-#{region}\"]" } }

    it 'only renders skeleton regions for the slots that are used' do
      render_inline described_class.new(heading: heading, loading: true) do |c|
        c.with_activity { 'Activity' }
        content
      end

      expect(page).to have_css(skeleton_region.call('content'))
      expect(page).to have_css(skeleton_region.call('activity'))
      expect(page).not_to have_css(skeleton_region.call('sidebar'))
      expect(page).not_to have_css(skeleton_region.call('widgets'))
      expect(page).not_to have_css('.gl-detail-layout-container-has-sidebar')
    end

    it 'renders all skeleton regions when all slots are used' do
      render_inline described_class.new(heading: heading, loading: true) do |c|
        c.with_sidebar { sidebar }
        c.with_widgets { 'Widgets' }
        c.with_activity { 'Activity' }
        content
      end

      %w[content sidebar widgets activity].each do |region|
        expect(page).to have_css(skeleton_region.call(region))
      end
      expect(page).to have_css('[data-testid="detail-layout-skeleton"].gl-detail-layout-container-has-sidebar')
      expect(page).not_to have_css('[data-testid="detail-layout-container"]')
    end

    it 'renders a custom loading slot instead of the detail skeleton' do
      render_inline described_class.new(heading: heading, loading: true) do |c|
        c.with_loading { 'Custom loading' }
        c.with_sidebar { sidebar }
        content
      end

      expect(page).to have_text('Custom loading')
      expect(page).not_to have_css('[data-testid="detail-layout-skeleton"]')
    end
  end

  describe 'slots' do
    describe 'sidebar' do
      it 'renders sidebar content when slot is provided' do
        render_inline described_class.new(heading: heading) do |c|
          c.with_sidebar { sidebar }
          content
        end

        expect(page).to have_css('[data-testid="detail-layout-sidebar"]', text: sidebar)
      end

      it 'renders sidebar after content by default' do
        render_inline described_class.new(heading: heading) do |c|
          c.with_sidebar { sidebar }
          content
        end

        expect(page).to have_css(
          '[data-testid="detail-layout-content"] + [data-testid="detail-layout-sidebar"]'
        )
      end

      context 'when sidebar_first is true' do
        it 'renders sidebar before content' do
          render_inline described_class.new(heading: heading, sidebar_first: true) do |c|
            c.with_sidebar { sidebar }
            content
          end

          expect(page).to have_css(
            '[data-testid="detail-layout-sidebar"] + [data-testid="detail-layout-content"]'
          )
          expect(page).to have_css('[data-testid="detail-layout-sidebar"]', count: 1)
        end
      end
    end

    describe 'widgets' do
      let(:widgets) { 'Widgets' }

      it 'renders widgets content when slot is provided' do
        render_inline described_class.new(heading: heading) do |c|
          c.with_widgets { widgets }
          content
        end

        expect(page).to have_css('[data-testid="detail-layout-widgets"]', text: widgets)
      end

      it 'does not render when no widgets slot is provided' do
        render_inline described_class.new(heading: heading) { content }

        expect(page).not_to have_css('[data-testid="detail-layout-widgets"]')
      end
    end

    describe 'activity' do
      let(:activity) { 'Activity' }

      it 'renders activity content when slot is provided' do
        render_inline described_class.new(heading: heading) do |c|
          c.with_activity { activity }
          content
        end

        expect(page).to have_css('[data-testid="detail-layout-activity"]', text: activity)
      end

      it 'does not render when no activity slot is provided' do
        render_inline described_class.new(heading: heading) { content }

        expect(page).not_to have_css('[data-testid="detail-layout-activity"]')
      end
    end

    describe 'default' do
      it 'renders body when default slot is provided' do
        render_inline described_class.new(heading: heading) do
          content
        end

        expect(page).to have_css('[data-testid="detail-layout-content"]', text: content)
      end
    end
  end
end
