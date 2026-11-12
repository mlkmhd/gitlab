# frozen_string_literal: true

require "spec_helper"

RSpec.shared_examples 'a base layout component' do
  let(:heading) { 'Page heading' }
  let(:description) { 'Page description' }
  let(:alerts_content) { 'Alert message' }
  let(:content) { 'Default content' }

  describe 'PageHeading' do
    describe 'heading' do
      it 'renders when heading prop is provided' do
        render_inline described_class.new(heading: heading)

        expect(page).to have_css('[data-testid="page-heading"]', text: heading)
      end

      it 'renders when heading slot is provided' do
        render_inline described_class.new do |c|
          c.with_heading { 'Custom Heading' }
        end

        expect(page).to have_css('[data-testid="page-heading"]', text: 'Custom Heading')
      end
    end

    describe 'description' do
      it 'renders description when prop provided' do
        render_inline described_class.new(heading: heading, description: description)

        expect(page).to have_css('[data-testid="page-heading-description"]', text: description)
      end

      it 'renders description when slot provided' do
        render_inline described_class.new(heading: heading) do |c|
          c.with_description { 'Test description' }
        end

        expect(page).to have_css('[data-testid="page-heading-description"]', text: 'Test description')
      end

      it 'does not render when no description prop or slot is provided' do
        render_inline described_class.new(heading: heading)

        expect(page).not_to have_css('[data-testid="page-heading-description"]')
      end
    end

    describe 'actions' do
      it 'renders actions when slot provided' do
        render_inline described_class.new(heading: heading) do |c|
          c.with_actions { 'Test action' }
        end

        expect(page).to have_css('[data-testid="page-heading-actions"]', text: 'Test action')
      end

      it 'does not render when no actions slot is provided' do
        render_inline described_class.new(heading: heading)

        expect(page).not_to have_css('[data-testid="page-heading-actions"]')
      end
    end
  end

  describe 'page_heading_sr_only' do
    it 'does not apply gl-sr-only class by default' do
      render_inline described_class.new(heading: heading)
      expect(page).not_to have_css('.gl-sr-only')
    end

    it 'applies gl-sr-only class when page_heading_sr_only is true' do
      render_inline described_class.new(heading: heading, page_heading_sr_only: true)
      expect(page).to have_css('.gl-sr-only')
    end
  end

  describe 'loading' do
    let(:skeleton) { '[data-testid="base-layout-skeleton"]' }
    let(:heading_skeleton) { '[data-testid="base-layout-heading-skeleton"]' }
    let(:description_skeleton) { '[data-testid="base-layout-description-skeleton"]' }

    it 'renders the skeleton with a status label when loading is true' do
      render_inline(described_class.new(heading: heading, loading: true)) { content }

      expect(page).to have_css("#{skeleton}[role=status]", text: 'Loading')
    end

    it 'does not render the skeleton when loading is false' do
      render_inline(described_class.new(heading: heading, loading: false)) { content }

      expect(page).not_to have_css(skeleton)
      expect(page).not_to have_css(heading_skeleton)
      expect(page).not_to have_css(description_skeleton)
    end

    it 'does not render content slot when loading' do
      render_inline(described_class.new(heading: heading, loading: true)) { content }

      expect(page).not_to have_css('[data-testid="base-layout-content"]', text: content)
    end

    it 'renders content slot when not loading' do
      render_inline(described_class.new(heading: heading, loading: false)) { content }

      expect(page).to have_css('[data-testid="base-layout-content"]', text: content)
    end

    it 'does not render a spinner' do
      render_inline(described_class.new(heading: heading, loading: true)) { content }

      expect(page).not_to have_css('.gl-spinner')
    end

    describe 'heading and description skeletons' do
      it 'renders them when heading and description are empty' do
        render_inline described_class.new(loading: true)

        expect(page).to have_css(heading_skeleton)
        expect(page).to have_css(description_skeleton)
      end

      it 'does not render the heading element while the heading skeleton shows' do
        render_inline described_class.new(loading: true)

        expect(page).to have_css(heading_skeleton)
        expect(page).not_to have_css('h1')
        expect(page).not_to have_css('[data-testid="page-heading"]')
      end

      it 'keeps heading and description props' do
        render_inline described_class.new(heading: heading, description: description, loading: true)

        expect(page).not_to have_css(heading_skeleton)
        expect(page).not_to have_css(description_skeleton)
        expect(page).to have_css('[data-testid="page-heading"]', text: heading)
        expect(page).to have_css('[data-testid="page-heading-description"]', text: description)
      end

      it 'keeps heading and description slots' do
        render_inline described_class.new(loading: true) do |c|
          c.with_heading { 'Custom Heading' }
          c.with_description { 'Custom description' }
        end

        expect(page).not_to have_css(heading_skeleton)
        expect(page).not_to have_css(description_skeleton)
        expect(page).to have_css('[data-testid="page-heading"]', text: 'Custom Heading')
        expect(page).to have_css('[data-testid="page-heading-description"]', text: 'Custom description')
      end

      it 'renders heading and description slots when not loading' do
        render_inline described_class.new(loading: false) do |c|
          c.with_heading { 'Custom Heading' }
          c.with_description { 'Custom description' }
        end

        expect(page).not_to have_css(heading_skeleton)
        expect(page).to have_css('[data-testid="page-heading"]', text: 'Custom Heading')
        expect(page).to have_css('[data-testid="page-heading-description"]', text: 'Custom description')
      end
    end

    context 'when a custom loading slot is provided' do
      it 'renders only the loading slot' do
        render_inline described_class.new(loading: true) do |c|
          c.with_loading { 'Custom loading' }
          content
        end

        expect(page).to have_css('[data-testid="base-layout-content"]', text: 'Custom loading')
        expect(page).not_to have_css(skeleton)
        expect(page).not_to have_css(heading_skeleton)
        expect(page).not_to have_css(description_skeleton)
        expect(page).not_to have_css('[data-testid="base-layout-content"]', text: content)
      end

      it 'does not render the loading slot when not loading' do
        render_inline described_class.new(loading: false) do |c|
          c.with_loading { 'Custom loading' }
          content
        end

        expect(page).not_to have_text('Custom loading')
        expect(page).to have_css('[data-testid="base-layout-content"]', text: content)
      end
    end
  end

  describe 'slots' do
    describe 'alerts' do
      it 'renders alert content when slot is provided' do
        render_inline described_class.new(heading: heading) do |c|
          c.with_alerts { alerts_content }
        end
        expect(page).to have_css('[data-testid="base-layout-alerts"]', text: alerts_content)
      end

      it 'does not render when no alerts slot is provided' do
        render_inline described_class.new(heading: heading)
        expect(page).not_to have_css('[data-testid="base-layout-alerts"]')
      end
    end

    describe 'default' do
      it 'renders body when default slot is provided' do
        render_inline described_class.new(heading: heading) do
          content
        end

        expect(page).to have_css('[data-testid="base-layout-content"]', text: content)
      end
    end
  end
end
