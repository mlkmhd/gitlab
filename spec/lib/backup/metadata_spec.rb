# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Backup::Metadata, feature_category: :backup_restore do
  let(:tmpdir) { Dir.mktmpdir }
  let(:manifest_filepath) { File.join(tmpdir, 'backup_information.yml') }
  let(:backup_created_at) { ActiveSupport::TimeZone['UTC'].local(2024, 1, 1, 12, 30) }

  subject(:metadata) { described_class.new(manifest_filepath) }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe '#save!' do
    before do
      metadata.update( # rubocop:disable Rails/SaveBang -- Backup::Metadata#update is not Active Record
        db_version: '20240101120000',
        backup_created_at: backup_created_at,
        gitlab_version: '16.11.0-pre',
        backup_id: '1704112200_2024_01_01_16.11.0-pre'
      )
    end

    it 'writes a manifest that can be loaded back', :aggregate_failures do
      metadata.save!

      backup_information = described_class.new(manifest_filepath).load!

      expect(backup_information.db_version).to eq('20240101120000')
      expect(backup_information.backup_created_at).to eq(backup_created_at)
      expect(backup_information.backup_created_at).to be_an_instance_of(Time)
      expect(backup_information.gitlab_version).to eq('16.11.0-pre')
      expect(backup_information.backup_id).to eq('1704112200_2024_01_01_16.11.0-pre')
    end

    context 'when backup_created_at shares one Time object between its utc and time values' do
      # Rails 8.1 does this for zones at a zero UTC offset, which makes a dumped TimeWithZone emit a YAML alias.
      before do
        allow(backup_created_at).to receive(:time).and_return(backup_created_at.utc)
      end

      it 'writes a manifest without YAML aliases', :aggregate_failures do
        metadata.save!

        nodes = YAML.parse_file(manifest_filepath).each.to_a

        expect(nodes.grep(Psych::Nodes::Alias)).to be_empty
        expect(described_class.new(manifest_filepath).load!.backup_created_at).to eq(backup_created_at)
      end
    end

    context 'when backup_created_at is not set' do
      let(:backup_created_at) { nil }

      it 'writes an empty value' do
        metadata.save!

        expect(described_class.new(manifest_filepath).load!.backup_created_at).to be_nil
      end
    end
  end
end
