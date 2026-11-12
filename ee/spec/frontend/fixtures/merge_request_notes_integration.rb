# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Merge request notes Integration (REST fixtures)', type: :request, feature_category: :code_review_workflow do
  include JavaScriptFixturesHelpers

  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:user) { create(:user, :with_namespace, maintainer_of: project) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project) }
  # Authored by someone else, so the recorded can_edit comes from the maintainer role.
  let_it_be(:note) { create(:note_on_merge_request, noteable: merge_request, project: project) }
  let_it_be(:diff_note) { create(:diff_note_on_merge_request, noteable: merge_request, project: project) }

  before do
    sign_in(user)
  end

  it 'merge_request_notes/integration/discussions.json' do
    get discussions_project_merge_request_path(project, merge_request, format: :json)

    expect(response).to have_gitlab_http_status(:ok)
    expect(json_response.flat_map { |discussion| discussion['notes'] })
      .to contain_exactly(recorded_note(note), recorded_note(diff_note))
  end

  # The #js-vue-mr-discussions dataset as the MR page renders it, keyed like `el.dataset`.
  describe 'discussions root dataset' do
    let(:response) do
      get project_merge_request_path(project, merge_request)

      attributes = Nokogiri::HTML(integration_session.response.body).at_css('#js-vue-mr-discussions').attributes
      data_attributes = attributes.select { |name, _| name.start_with?('data-') }

      data_attributes.to_h do |name, attr|
        [name.delete_prefix('data-').underscore.camelize(:lower), attr.value]
      end.to_json
    end

    it 'merge_request_notes/integration/discussions_root_dataset.json' do
      expect(response).to include('notesData', 'currentUserData', 'reportAbusePath')
    end
  end

  private

  # The fields reportable_note_spec.js reads. A shape change fails here instead of
  # passing the Jest spec against a stale fixture.
  def recorded_note(note)
    a_hash_including(
      'id' => note.id.to_s,
      'author' => a_hash_including('id' => note.author.id),
      'noteable_note_url' => Gitlab::UrlBuilder.build(note),
      'current_user' => a_hash_including('can_edit' => true)
    )
  end
end
