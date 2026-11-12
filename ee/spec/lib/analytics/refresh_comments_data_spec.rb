# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::RefreshCommentsData do
  describe '.for_note' do
    subject { described_class.for_note(note, eligible_only: eligible_only) }

    let(:eligible_only) { true }

    context 'for non-commit, non-mr note' do
      let(:note) { create(:note, :on_issue) }

      it { is_expected.to be_nil }
    end

    context 'for MR note' do
      let(:note) { create(:note, :on_merge_request, author: create(:user)) }

      it 'returns refresh comments instance for note MR' do
        expected_mock = instance_double(described_class)

        allow(described_class).to receive(:new).with(note.noteable).and_return(expected_mock)

        expect(subject).to eq expected_mock
      end
    end

    context 'for MR note by a non-human author' do
      let(:note) { create(:note, :on_merge_request, author: create(:user, :project_bot)) }

      it { is_expected.to be_nil }
    end

    context 'for MR note by a service account' do
      let(:note) { create(:note, :on_merge_request, author: create(:user, :service_account)) }

      it { is_expected.to be_nil }
    end

    context 'for MR note without an author' do
      let(:note) { build_stubbed(:note, :on_merge_request, author: nil) }

      it { is_expected.to be_nil }
    end

    context 'for MR note owned by the ghost user' do
      let(:note) { create(:note, :on_merge_request, author: create(:user, :ghost)) }

      it { is_expected.to be_nil }

      context 'without eligible_only, as on note deletion' do
        let(:eligible_only) { false }

        it 'includes the MR so first_comment_at gets recomputed' do
          expect(described_class).to receive(:new).with(note.noteable).and_call_original

          subject
        end
      end
    end

    context 'for MR note by the MR author' do
      let(:merge_request) { create(:merge_request) }
      let(:note) do
        create(:note, noteable: merge_request, project: merge_request.project, author: merge_request.author)
      end

      it { is_expected.to be_nil }

      context 'without eligible_only, as on note deletion' do
        let(:eligible_only) { false }

        it 'includes the MR' do
          expect(described_class).to receive(:new).with(merge_request).and_call_original

          subject
        end
      end
    end

    context 'for MR note when the MR author was deleted' do
      let(:merge_request) { create(:merge_request) }
      let(:note) { create(:note, noteable: merge_request, project: merge_request.project, author: create(:user)) }

      before do
        merge_request.update_column(:author_id, nil)
      end

      it 'includes the MR' do
        expect(described_class).to receive(:new).with(merge_request).and_call_original

        subject
      end
    end

    context 'for commit note' do
      let(:note) { create(:diff_note_on_commit, author: create(:user)) }
      let!(:merge_request) { create :merge_request, source_project: note.project }

      before do
        allow(note.noteable).to receive(:merge_requests).and_return(note.project.merge_requests)
      end

      it 'returns refresh comments instance for commit MR' do
        expected_mock = instance_double(described_class)

        allow(described_class).to receive(:new).with(merge_request).and_return(expected_mock)

        expect(subject).to eq expected_mock
      end
    end
  end

  describe '#execute' do
    subject { described_class.new(merge_request) }

    let(:merge_request) { create :merge_request }
    let(:calculated_value) { 2.days.ago.beginning_of_day }

    include_examples 'common merge request metric refresh for', :first_comment_at
  end
end
