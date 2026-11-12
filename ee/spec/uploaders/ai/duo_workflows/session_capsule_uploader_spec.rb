# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SessionCapsuleUploader, feature_category: :duo_agent_platform do
  # Stands in for the SessionCapsule model, which a later change adds. ObjectStorage reads
  # uploader_options from the model class.
  let(:capsule_class) do
    Struct.new(:id, :namespace_id) do
      def self.uploader_options
        {}
      end
    end
  end

  let(:capsule) { capsule_class.new(1, 2) }
  let(:uploader) { described_class.new(capsule) }

  subject { uploader }

  it_behaves_like "builds correct paths",
    store_dir: %r{\A\h{2}/\h{2}/\h{64}/session_capsules/1\z},
    cache_dir: %r{/duo_session_capsules/tmp/cache\z},
    work_dir: %r{/duo_session_capsules/tmp/work\z}

  describe '.default_store' do
    context 'when object storage is enabled' do
      before do
        allow(described_class).to receive(:object_store_enabled?).and_return(true)
      end

      it 'returns REMOTE' do
        expect(described_class.default_store).to eq(ObjectStorage::Store::REMOTE)
      end
    end

    context 'when object storage is disabled' do
      before do
        allow(described_class).to receive(:object_store_enabled?).and_return(false)
      end

      it 'returns LOCAL' do
        expect(described_class.default_store).to eq(ObjectStorage::Store::LOCAL)
      end
    end
  end

  describe '.workhorse_local_upload_path' do
    it 'is under public/uploads/tmp, which Gitlab::Middleware::Multipart accepts' do
      expect(described_class.workhorse_local_upload_path)
        .to start_with(Rails.root.join('public/uploads/tmp/').to_s)
    end
  end

  describe '.workhorse_authorize' do
    context 'when object storage is disabled' do
      before do
        allow(described_class).to receive(:object_store_enabled?).and_return(false)
      end

      it 'tells Workhorse to write the upload to the local upload path' do
        expect(described_class.workhorse_authorize(has_length: false, maximum_size: 1.megabyte)).to include(
          TempPath: described_class.workhorse_local_upload_path,
          MaximumSize: 1.megabyte
        )
      end
    end
  end

  describe '#store_dir' do
    context 'when the capsule is not persisted' do
      let(:capsule) { capsule_class.new(nil, 2) }

      it 'raises ObjectNotReadyError' do
        expect { uploader.store_dir }.to raise_error(
          GitlabUploader::ObjectNotReadyError,
          'SessionCapsule model not ready'
        )
      end
    end

    context 'when namespace_id is nil' do
      let(:capsule) { capsule_class.new(1, nil) }

      it 'raises ObjectNotReadyError' do
        expect { uploader.store_dir }.to raise_error(
          GitlabUploader::ObjectNotReadyError,
          'SessionCapsule model not ready'
        )
      end
    end

    context 'when namespace_id differs' do
      let(:other_uploader) { described_class.new(capsule_class.new(1, 3)) }

      it 'produces a different store_dir' do
        expect(uploader.store_dir.to_s).not_to eq(other_uploader.store_dir.to_s)
      end
    end
  end

  describe '#filename' do
    context 'when a file has been uploaded' do
      before do
        uploader.store!(CarrierWaveStringFile.new('test content'))
      end

      after do
        uploader.remove!
      end

      it 'returns capsule.tar' do
        expect(uploader.filename).to eq('capsule.tar')
      end
    end

    context 'when no file has been uploaded' do
      it 'returns nil' do
        expect(uploader.filename).to be_nil
      end
    end
  end
end
