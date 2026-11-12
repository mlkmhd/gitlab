# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Banzai::Filter::FootnoteFilter, feature_category: :markdown do
  using RSpec::Parameterized::TableSyntax

  context 'when a footnote is referenced more than once' do
    before do
      stub_env('GITLAB_TEST_FOOTNOTE_ID', '42')
    end

    it 'links every reference rendered from Markdown to its footnote and back', :aggregate_failures do
      markdown = "a[^1] b[^1]\n\nx[^my-note] y[^my-note]\n\n[^1]: one\n[^my-note]: two"
      doc = Banzai::Pipeline::FullPipeline.call(markdown, project: nil)[:output]

      ids = doc.css('[id]').map { |node| node[:id] }
      refs = doc.css('sup > a[data-footnote-ref]')
      backrefs = doc.css('section.footnotes a[data-footnote-backref]')
      targets = (refs + backrefs).map { |node| node[:href].delete_prefix('#') }

      expect(refs.size).to eq(4)
      expect(backrefs.size).to eq(4)
      expect(targets - ids).to be_empty
      expect(refs.map { |node| node[:id] }).to all(end_with('-42'))
      expect(refs.map { |node| node.parent[:class] }).to all(eq('footnote-ref'))
      expect(backrefs.map { |node| node[:class] }).to all(eq('footnote-backref'))
    end
  end

  context 'when detecting footnotes' do
    where(:valid, :markdown) do
      true   | "1. one[^1]\n[^1]: AbC"
      true   | "1. one[^abc]\n[^abc]: AbC"
      false  | '1. [one](#fnref-abc)'
      false  | "1. one[^1]\n[^abc]: AbC"
    end

    with_them do
      it 'detects valid footnotes' do
        result = Banzai::Pipeline::FullPipeline.call(markdown, project: nil)

        expect(result[:output].at_css('section.footnotes').present?).to eq(valid)
      end
    end
  end

  context 'when too many footnotes' do
    it 'ignores them all' do
      markdown = "[^1]\n[^1]:\n" * (Banzai::Filter::FootnoteFilter::FOOTNOTE_LIMIT + 1)
      result = Banzai::Pipeline::FullPipeline.call(markdown, project: nil)

      expect(result[:output].at_css('section.footnotes').present?).to be_falsey
    end
  end
end
