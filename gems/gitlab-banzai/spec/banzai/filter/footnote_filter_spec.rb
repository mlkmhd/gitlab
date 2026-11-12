# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Banzai::Filter::FootnoteFilter do
  include FilterSpecHelper

  # rubocop:disable Style/AsciiComments
  # first[^1] and second[^second] and third[^_😄_]
  # [^1]: one
  # [^second]: two
  # [^_😄_]: three
  # rubocop:enable Style/AsciiComments
  let(:footnote) do
    <<~HTML
      <p>first<sup><a href="#fn-1" id="fnref-1" data-footnote-ref>1</a></sup> and second<sup><a href="#fn-second" id="fnref-second" data-footnote-ref>2</a></sup> and third<sup><a href="#fn-_%F0%9F%98%84_" id="fnref-_%F0%9F%98%84_" data-footnote-ref>3</a></sup></p>
      <p>missing id<sup><a href="#fn-10" data-footnote-ref>1</a></sup></p>
      <section data-footnotes>
      <ol>
      <li id="fn-1">
      <p>one <a href="#fnref-1" data-footnote-backref data-footnote-backref-idx="1" aria-label="Back to reference 1" title="Back to reference 1">↩</a></p>
      </li>
      <li id="fn-second">
      <p>two <a href="#fnref-second" data-footnote-backref data-footnote-backref-idx="2" aria-label="Back to reference 2" title="Back to reference 2">↩</a></p>
      </li>\n<li id="fn-_%F0%9F%98%84_">
      <p>three <a href="#fnref-_%F0%9F%98%84_" data-footnote-backref data-footnote-backref-idx="3" aria-label="Back to reference 3" title="Back to reference 3">↩</a></p>
      </li>
      </ol>
    HTML
  end

  let(:filtered_footnote) do
    <<~HTML
      <p>first<sup class="footnote-ref"><a href="#fn-1-#{identifier}" id="fnref-1-#{identifier}" data-footnote-ref>1</a></sup> and second<sup class="footnote-ref"><a href="#fn-second-#{identifier}" id="fnref-second-#{identifier}" data-footnote-ref>2</a></sup> and third<sup class="footnote-ref"><a href="#fn-_%F0%9F%98%84_-#{identifier}" id="fnref-_%F0%9F%98%84_-#{identifier}" data-footnote-ref>3</a></sup></p>
      <p>missing id<sup><a href="#fn-10" data-footnote-ref>1</a></sup></p>
      <section data-footnotes class=\"footnotes\">
      <ol>
      <li id="fn-1-#{identifier}">
      <p>one <a href="#fnref-1-#{identifier}" data-footnote-backref data-footnote-backref-idx="1" aria-label="footnote_backref_title 1" title="footnote_backref_title 1" class="footnote-backref">↩</a></p>
      </li>
      <li id="fn-second-#{identifier}">
      <p>two <a href="#fnref-second-#{identifier}" data-footnote-backref data-footnote-backref-idx="2" aria-label="footnote_backref_title 2" title="footnote_backref_title 2" class="footnote-backref">↩</a></p>
      </li>
      <li id="fn-_%F0%9F%98%84_-#{identifier}">
      <p>three <a href="#fnref-_%F0%9F%98%84_-#{identifier}" data-footnote-backref data-footnote-backref-idx="3" aria-label="footnote_backref_title 3" title="footnote_backref_title 3" class="footnote-backref">↩</a></p>
      </li>
      </ol>
      </section>
    HTML
  end

  context 'when footnotes exist' do
    let(:doc)        { filter(footnote) }
    let(:link_node)  { doc.css('sup > a').first }
    let(:identifier) { link_node[:id].delete_prefix('fnref-1-') }

    it 'properly adds the necessary ids and classes' do
      expect(doc.to_html).to eq_html filtered_footnote.strip
    end

    context 'when GITLAB_TEST_FOOTNOTE_ID is set' do
      let(:test_footnote_id) { '42' }
      let(:identifier) { test_footnote_id }

      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('GITLAB_TEST_FOOTNOTE_ID', anything).and_return(test_footnote_id)
      end

      it 'uses the test footnote ID instead of a random number' do
        expect(doc.to_html).to eq_html filtered_footnote.strip
      end
    end
  end

  context 'when a footnote is referenced more than once' do
    # a[^1] b[^1] c[^1] and x[^my-note] y[^my-note]
    # [^1]: one
    # [^my-note]: two
    let(:footnote) do
      <<~HTML
        <p>a<sup><a href="#fn-1" id="fnref-1" data-footnote-ref>1</a></sup> b<sup><a href="#fn-1" id="fnref-1-2" data-footnote-ref>1</a></sup> c<sup><a href="#fn-1" id="fnref-1-3" data-footnote-ref>1</a></sup> and x<sup><a href="#fn-my-note" id="fnref-my-note" data-footnote-ref>2</a></sup> y<sup><a href="#fn-my-note" id="fnref-my-note-2" data-footnote-ref>2</a></sup></p>
        <section data-footnotes>
        <ol>
        <li id="fn-1">
        <p>one <a href="#fnref-1" data-footnote-backref data-footnote-backref-idx="1" aria-label="Back to reference 1">↩</a> <a href="#fnref-1-2" data-footnote-backref data-footnote-backref-idx="1-2" aria-label="Back to reference 1-2">↩<sup>2</sup></a> <a href="#fnref-1-3" data-footnote-backref data-footnote-backref-idx="1-3" aria-label="Back to reference 1-3">↩<sup>3</sup></a></p>
        </li>
        <li id="fn-my-note">
        <p>two <a href="#fnref-my-note" data-footnote-backref data-footnote-backref-idx="2" aria-label="Back to reference 2">↩</a> <a href="#fnref-my-note-2" data-footnote-backref data-footnote-backref-idx="2-2" aria-label="Back to reference 2-2">↩<sup>2</sup></a></p>
        </li>
        </ol>
        </section>
      HTML
    end

    let(:filtered_footnote) do
      <<~HTML
        <p>a<sup class="footnote-ref"><a href="#fn-1-42" id="fnref-1-42" data-footnote-ref>1</a></sup> b<sup class="footnote-ref"><a href="#fn-1-42" id="fnref-1-2-42" data-footnote-ref>1</a></sup> c<sup class="footnote-ref"><a href="#fn-1-42" id="fnref-1-3-42" data-footnote-ref>1</a></sup> and x<sup class="footnote-ref"><a href="#fn-my-note-42" id="fnref-my-note-42" data-footnote-ref>2</a></sup> y<sup class="footnote-ref"><a href="#fn-my-note-42" id="fnref-my-note-2-42" data-footnote-ref>2</a></sup></p>
        <section data-footnotes class="footnotes">
        <ol>
        <li id="fn-1-42">
        <p>one <a href="#fnref-1-42" data-footnote-backref data-footnote-backref-idx="1" aria-label="footnote_backref_title 1" title="footnote_backref_title 1" class="footnote-backref">↩</a> <a href="#fnref-1-2-42" data-footnote-backref data-footnote-backref-idx="1-2" aria-label="footnote_backref_title 1-2" title="footnote_backref_title 1-2" class="footnote-backref">↩<sup>2</sup></a> <a href="#fnref-1-3-42" data-footnote-backref data-footnote-backref-idx="1-3" aria-label="footnote_backref_title 1-3" title="footnote_backref_title 1-3" class="footnote-backref">↩<sup>3</sup></a></p>
        </li>
        <li id="fn-my-note-42">
        <p>two <a href="#fnref-my-note-42" data-footnote-backref data-footnote-backref-idx="2" aria-label="footnote_backref_title 2" title="footnote_backref_title 2" class="footnote-backref">↩</a> <a href="#fnref-my-note-2-42" data-footnote-backref data-footnote-backref-idx="2-2" aria-label="footnote_backref_title 2-2" title="footnote_backref_title 2-2" class="footnote-backref">↩<sup>2</sup></a></p>
        </li>
        </ol>
        </section>
      HTML
    end

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('GITLAB_TEST_FOOTNOTE_ID', anything).and_return('42')
    end

    it 'adds the suffix to every reference and back-reference' do
      expect(filter(footnote.strip).to_html).to eq_html filtered_footnote.strip
    end
  end

  context 'when a footnote name is not a valid CSS identifier' do
    let(:footnote) do
      <<~HTML.strip
        <p>a<sup><a href="#fn-a b" id="fnref-a b" data-footnote-ref>1</a></sup></p>
        <section data-footnotes><ol><li id="fn-a b"><p>one <a href="#fnref-a b" data-footnote-backref data-footnote-backref-idx="1">↩</a></p></li></ol></section>
      HTML
    end

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('GITLAB_TEST_FOOTNOTE_ID', anything).and_return('42')
    end

    it 'finds the footnote without building a selector from its name', :aggregate_failures do
      doc = filter(footnote)

      expect(doc.at_css('sup > a')[:href]).to eq('#fn-a b-42')
      expect(doc.at_css('section li')[:id]).to eq('fn-a b-42')
      expect(doc.at_css('section li a')[:href]).to eq('#fnref-a b-42')
    end
  end

  context 'when a reference has no back-reference, no footnote or no href' do
    let(:footnote) do
      <<~HTML.strip
        <p>a<sup><a href="#fn-1" id="fnref-1" data-footnote-ref>1</a></sup> b<sup><a href="#fn-1" id="fnref-1-2" data-footnote-ref>1</a></sup> c<sup><a href="#fn-missing" id="fnref-missing" data-footnote-ref>2</a></sup> d<sup><a id="fnref-no-href" data-footnote-ref>3</a></sup></p>
        <section data-footnotes><ol><li id="fn-1"><p>one <a href="#fnref-1" data-footnote-backref data-footnote-backref-idx="1">↩</a></p></li></ol></section>
      HTML
    end

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('GITLAB_TEST_FOOTNOTE_ID', anything).and_return('42')
    end

    it 'links the references it can and leaves the others as they are', :aggregate_failures do
      doc = filter(footnote)
      refs = doc.css('sup > a')

      expect(refs.map { |node| node[:href] }).to eq(['#fn-1-42', '#fn-1-42', '#fn-missing', nil])
      expect(refs.map { |node| node[:id] }).to eq(%w[fnref-1-42 fnref-1-2-42 fnref-missing fnref-no-href])
      expect(doc.at_css('section li a')[:href]).to eq('#fnref-1-42')
    end
  end

  it_behaves_like 'pipeline timing check'
end
