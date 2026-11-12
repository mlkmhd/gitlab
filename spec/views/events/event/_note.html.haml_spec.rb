# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'events/event/_note.html.haml', feature_category: :user_profile do
  let(:project) { build_stubbed(:project) }
  let(:user) { build_stubbed(:user) }
  let(:issue) { build_stubbed(:issue, project: project) }
  let(:note) { build_stubbed(:note_on_issue, noteable: issue, project: project, author: user) }
  let(:event) { build_stubbed(:event, :commented, project: project, target: note, author: user) }

  it 'renders the localized action name' do
    allow(view).to receive(:localized_action_name).and_return('localized commented on')

    render partial: 'events/event/note', locals: { event: event.present }

    expect(rendered).to have_css('.event-type', text: 'localized commented on')
  end
end
