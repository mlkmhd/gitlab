# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DiffViewer::Image do
  describe '.can_render?' do
    let(:diff_file) { double(Gitlab::Diff::File) }
    let(:blob) { double(Gitlab::Git::Blob, binary_in_repo?: true, extension: 'png') }

    subject { described_class.can_render?(diff_file, verify_binary: false) }

    it 'returns false if both old and new blob are absent' do
      allow(diff_file).to receive_messages(old_blob: nil, new_blob: nil)

      is_expected.to be_falsy
    end

    it 'returns true if the old blob is present' do
      allow(diff_file).to receive(:old_blob) { blob }
      allow(diff_file).to receive(:new_blob).and_return(nil)

      is_expected.to be_truthy
    end

    it 'returns true if the new blob is present' do
      allow(diff_file).to receive(:old_blob).and_return(nil)
      allow(diff_file).to receive(:new_blob) { blob }

      is_expected.to be_truthy
    end

    it 'returns true if both old and new blobs are present' do
      allow(diff_file).to receive(:old_blob) { blob }
      allow(diff_file).to receive(:new_blob) { blob }

      is_expected.to be_truthy
    end
  end

  describe '#collapsed?' do
    let(:diff_file) do
      instance_double(
        Gitlab::Diff::File,
        binary_in_repo?: true, collapsed?: true, generated?: generated, expanded?: false, raw_size: raw_size
      )
    end

    let(:generated) { false }

    subject { described_class.new(diff_file).collapsed? }

    context 'when the diff collection collapsed the file' do
      let(:raw_size) { 1.kilobyte }

      it { is_expected.to be(false) }

      it 'memoizes the result' do
        viewer = described_class.new(diff_file)
        viewer.collapsed?

        expect(diff_file).not_to receive(:raw_size)
        expect(viewer.collapsed?).to be(false)
      end
    end

    context 'when the diff collection did not collapse the file' do
      let(:raw_size) { 1.kilobyte }

      before do
        allow(diff_file).to receive(:collapsed?).and_return(false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the diff collection collapsed a generated file' do
      let(:raw_size) { 1.kilobyte }
      let(:generated) { true }

      it { is_expected.to be(true) }
    end

    context 'when the image is over the collapse limit' do
      let(:raw_size) { 2.megabytes }

      it { is_expected.to be(true) }
    end
  end
end
