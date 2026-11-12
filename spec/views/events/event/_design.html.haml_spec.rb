# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'events/event/_design.html.haml', feature_category: :user_profile do
  let(:event) { build_stubbed(:design_event) }

  it 'renders the localized action name' do
    allow(view).to receive(:localized_action_name).and_return('localized added')

    render partial: 'events/event/design', locals: { event: event.present }

    expect(rendered).to have_css('.event-type', text: 'localized added')
  end
end
