# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'projects/settings/_git_throttle_limits', feature_category: :rate_limiting do
  let(:project) { build_stubbed(:project) }
  let(:user) { build_stubbed(:user) }

  before do
    assign(:project, project)
    allow(view).to receive_messages(current_user: user, expanded_by_default?: true)
    allow(view).to receive(:can?).with(user, :update_git_rate_limit, project).and_return(true)
  end

  # The help text sits after the input, so a screen reader tabbing to the field
  # would otherwise announce only the short label and miss "leave blank to use
  # the instance limit".
  it 'describes every input with its help text' do
    render

    doc = Nokogiri::HTML.fragment(rendered)
    inputs = doc.css('input[type="number"]')

    expect(inputs).not_to be_empty

    inputs.each do |input|
      described_by = input['aria-describedby']

      expect(described_by).to be_present,
        "expected #{input['name']} to carry aria-describedby"
      expect(doc.at_css("##{described_by}")).to be_present,
        "expected an element with id #{described_by} to describe #{input['name']}"
      expect(doc.at_css("##{described_by}").text).to be_present
    end
  end

  context 'when the user cannot update the Git rate limit' do
    before do
      allow(view).to receive(:can?).with(user, :update_git_rate_limit, project).and_return(false)
    end

    # The partial returns before it writes anything, so ActionView hands back nil
    # rather than an empty buffer, which the view-spec `render` helper cannot hold.
    it 'renders nothing' do
      view.assign(view_assigns)

      expect(view.render(partial: 'projects/settings/git_throttle_limits')).to be_nil
    end
  end
end
