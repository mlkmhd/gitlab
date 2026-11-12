# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sbom::TrackPolicyDismissalOccurrenceRefsWorker, feature_category: :dependency_management do
  let_it_be(:policy_dismissal) { create(:policy_dismissal, :preserved) }

  let(:policy_dismissal_id) { policy_dismissal.id }
  let(:event) do
    Security::PolicyDismissalPreservedEvent.new(data: { security_policy_dismissal_id: policy_dismissal_id })
  end

  let(:indexing_allowed) { true }

  subject(:use_event) { consume_event(subscriber: described_class, event: event) }

  before do
    allow(::Search::Elastic::SbomOccurrenceRefIndexHelper).to receive(:indexing_allowed?).and_return(indexing_allowed)
  end

  it_behaves_like 'worker with data consistency', described_class, data_consistency: :sticky
  it_behaves_like 'subscribes to event'

  context 'when the track_sbom_occurrence_refs_on_policy_dismissal_preserved feature flag is disabled' do
    before do
      stub_feature_flags(track_sbom_occurrence_refs_on_policy_dismissal_preserved: false)
    end

    it_behaves_like 'ignores the published event'
  end

  context 'when SBOM occurrence ref indexing is not allowed' do
    let(:indexing_allowed) { false }

    it_behaves_like 'ignores the published event'
  end

  it 'tracks the occurrence refs the dismissal covers' do
    expect_next_instance_of(Sbom::TrackPolicyDismissalOccurrenceRefsService, policy_dismissal) do |service|
      expect(service).to receive(:execute)
    end

    use_event
  end

  context 'when the dismissal no longer exists' do
    let(:policy_dismissal_id) { non_existing_record_id }

    it 'does nothing' do
      expect(Sbom::TrackPolicyDismissalOccurrenceRefsService).not_to receive(:new)

      use_event
    end
  end
end
