# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['SystemNoteMetadata'], feature_category: :team_planning do
  include GraphqlHelpers

  it { expect(described_class).to have_graphql_field(:description_diff_available) }

  describe '#description_diff_available' do
    let_it_be(:user) { create(:user) }
    let_it_be(:project) { create(:project, :public) }
    let_it_be(:issue) { create(:issue, project: project) }
    let_it_be(:note) { create(:note, :system, noteable: issue, project: project) }

    let(:description_version) { create(:description_version, issue: issue) }
    let(:metadata) { create(:system_note_metadata, note: note, description_version: description_version) }

    subject(:description_diff_available) { resolve_field(:description_diff_available, metadata, current_user: user) }

    before do
      stub_licensed_features(description_diffs: true)
    end

    it { is_expected.to be(true) }

    context 'when the system note has no description version' do
      let(:description_version) { nil }

      it { is_expected.to be(false) }
    end

    context 'when the description version is deleted' do
      let(:description_version) { create(:description_version, issue: issue, deleted_at: Time.current) }

      it { is_expected.to be(false) }
    end

    context 'when the description version has no issuable' do
      before do
        allow(description_version).to receive(:issuable).and_return(nil)
      end

      it { is_expected.to be(false) }
    end

    context 'when description_diffs is not licensed' do
      before do
        stub_licensed_features(description_diffs: false)
      end

      it { is_expected.to be(false) }
    end
  end
end
