# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sbom::TrackPolicyDismissalOccurrenceRefsService, feature_category: :dependency_management do
  let_it_be(:project) { create(:project) }

  let_it_be(:dismissed_occurrence) { create(:sbom_occurrence, project: project) }
  let_it_be(:other_occurrence) { create(:sbom_occurrence, project: project) }

  let_it_be(:first_dismissed_ref) { create(:sbom_occurrence_ref, occurrence: dismissed_occurrence, project: project) }
  let_it_be(:second_dismissed_ref) { create(:sbom_occurrence_ref, occurrence: dismissed_occurrence, project: project) }
  let_it_be(:other_occurrence_ref) { create(:sbom_occurrence_ref, occurrence: other_occurrence, project: project) }

  let(:license_occurrence_uuids) { [dismissed_occurrence.uuid] }
  let(:policy_dismissal) do
    create(:policy_dismissal, :preserved, project: project, license_occurrence_uuids: license_occurrence_uuids)
  end

  let(:indexing_allowed) { true }

  subject(:execute) { described_class.new(policy_dismissal).execute }

  before do
    allow(::Search::Elastic::SbomOccurrenceRefIndexHelper).to receive(:indexing_allowed?).and_return(indexing_allowed)
  end

  describe '#execute' do
    it 'tracks every ref of the dismissed occurrences' do
      tracked_refs = []

      allow(::Sbom::BulkEsOperationService).to receive(:new) do |relation|
        tracked_refs.concat(relation.to_a)

        instance_double(::Sbom::BulkEsOperationService, execute: true)
      end

      execute

      expect(tracked_refs).to match_array([first_dismissed_ref, second_dismissed_ref])
    end

    context 'when the dismissal covers more uuids than the batch size' do
      let(:license_occurrence_uuids) { [dismissed_occurrence.uuid, other_occurrence.uuid] }

      before do
        stub_const("#{described_class}::BATCH_SIZE", 1)
      end

      it 'tracks the refs of each batch of uuids separately' do
        tracked_batches = []

        allow(::Sbom::BulkEsOperationService).to receive(:new) do |relation|
          tracked_batches << relation.to_a

          instance_double(::Sbom::BulkEsOperationService, execute: true)
        end

        execute

        expect(tracked_batches).to contain_exactly(
          match_array([first_dismissed_ref, second_dismissed_ref]),
          [other_occurrence_ref]
        )
      end
    end

    context 'when the dismissal covers no occurrences' do
      let(:license_occurrence_uuids) { [] }

      it 'does not track any occurrence refs' do
        expect(::Sbom::BulkEsOperationService).not_to receive(:new)

        execute
      end
    end

    context 'when indexing is not allowed' do
      let(:indexing_allowed) { false }

      it 'does not track any occurrence refs' do
        expect(::Sbom::BulkEsOperationService).not_to receive(:new)

        execute
      end
    end
  end
end
