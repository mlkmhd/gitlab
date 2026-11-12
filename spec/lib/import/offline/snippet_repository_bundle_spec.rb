# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Offline::SnippetRepositoryBundle, feature_category: :importers do
  let_it_be(:project) { create(:project) }
  let_it_be(:snippet_with_repository) { create(:project_snippet, :repository, project: project) }
  let_it_be(:snippet_without_repository) { create(:project_snippet, project: project) }

  describe '.filename_for' do
    it 'returns a bundle filename derived from the snippet attributes' do
      filename = described_class.filename_for(snippet_with_repository)

      expect(filename).to match(/\A\h{64}\.bundle\z/)
      expect(filename).to eq(described_class.filename_for(snippet_with_repository))
      expect(filename).not_to eq(described_class.filename_for(snippet_without_repository))
    end

    it 'does not depend on the configured time zone' do
      utc_filename = Time.use_zone('UTC') { described_class.filename_for(snippet_with_repository) }
      tokyo_filename = Time.use_zone('Tokyo') { described_class.filename_for(snippet_with_repository) }

      expect(tokyo_filename).to eq(utc_filename)
    end

    it 'does not depend on attributes that can change between relation exports' do
      created_at = Time.zone.parse('2020-01-02T03:04:05.100123Z')
      original = build(:project_snippet, title: 'title', description: 'original', created_at: created_at)
      changed = build(
        :project_snippet,
        title: 'title',
        description: 'changed',
        created_at: created_at + 0.0005.seconds,
        updated_at: 1.day.from_now
      )

      expect(described_class.filename_for(changed)).to eq(described_class.filename_for(original))
    end

    it 'distinguishes snippets created in the same second but a different millisecond' do
      created_at = Time.zone.parse('2020-01-02T03:04:05.100Z')
      first = build(:project_snippet, title: 'title', created_at: created_at)
      second = build(:project_snippet, title: 'title', created_at: created_at + 0.001.seconds)

      expect(described_class.filename_for(first)).not_to eq(described_class.filename_for(second))
    end

    it 'matches the created_at precision that survives the NDJSON round trip' do
      source = build(:project_snippet, title: 'title', created_at: Time.zone.parse('2020-01-02T03:04:05.444650Z'))
      imported = build(:project_snippet, title: 'title', created_at: Time.zone.parse(source.created_at.as_json))

      expect(described_class.filename_for(imported)).to eq(described_class.filename_for(source))
    end

    it 'distinguishes titles that only differ in where they end' do
      created_at = Time.zone.parse('2020-01-02T03:04:05Z')
      first = build(:project_snippet, title: '2020', created_at: created_at)
      second = build(:project_snippet, title: '202', created_at: created_at)

      expect(described_class.filename_for(first)).not_to eq(described_class.filename_for(second))
    end
  end

  describe '.ambiguous_filenames' do
    it 'returns an empty set when every snippet maps to a distinct filename' do
      expect(described_class.ambiguous_filenames(project)).to be_empty
    end

    context 'when snippets share a title and creation millisecond' do
      let_it_be(:other_project) { create(:project) }
      let_it_be(:created_at) { Time.zone.parse('2020-01-02T03:04:05.100Z') }
      let_it_be(:duplicates) do
        [
          create(:project_snippet, project: other_project, title: 'dup', created_at: created_at),
          create(:project_snippet, project: other_project, title: 'dup', created_at: created_at + 0.0005.seconds)
        ]
      end

      let_it_be(:unique_snippet) do
        create(:project_snippet, project: other_project, title: 'dup', created_at: created_at + 0.001.seconds)
      end

      it 'returns only the shared filename' do
        expect(described_class.ambiguous_filenames(other_project))
          .to contain_exactly(described_class.filename_for(duplicates.first))
      end

      it 'finds duplicates that fall in different batches' do
        stub_const("#{described_class}::BATCH_SIZE", 1)

        expect(described_class.ambiguous_filenames(other_project))
          .to contain_exactly(described_class.filename_for(duplicates.first))
      end
    end
  end
end
