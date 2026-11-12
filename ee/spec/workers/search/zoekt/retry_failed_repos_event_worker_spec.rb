# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Zoekt::RetryFailedReposEventWorker, :zoekt_settings_enabled, feature_category: :global_search do
  let(:event) { Search::Zoekt::RetryFailedReposEvent.build }

  let_it_be(:failed_repos) do
    create_list(:zoekt_repository, 3, state: :failed, retries_left: 0, updated_at: 1.hour.ago)
  end

  let_it_be(:ready_repo) { create(:zoekt_repository, state: :ready) }

  it_behaves_like 'subscribes to event'

  it_behaves_like 'an idempotent worker' do
    it 'moves failed repositories back to pending with one retry', :freeze_time do
      expect(Gitlab::EventStore).not_to receive(:publish)

      consume_event(subscriber: described_class, event: event)

      expect(failed_repos.map(&:reload))
        .to all(have_attributes(state: 'pending', retries_left: 1, updated_at: Time.current))
      expect(ready_repo.reload).to be_ready
    end
  end

  context 'when there are more failed repositories than the batch size' do
    before do
      stub_const("#{described_class}::BATCH_SIZE", 2)
    end

    it 'retries one batch and publishes another event' do
      expect(Gitlab::EventStore).to receive(:publish)
        .with(an_object_having_attributes(class: Search::Zoekt::RetryFailedReposEvent))

      expect { consume_event(subscriber: described_class, event: event) }
        .to change { Search::Zoekt::Repository.failed.count }.from(3).to(1)
    end
  end
end
