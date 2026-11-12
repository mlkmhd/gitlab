# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Zoekt::NodeWithNegativeUnclaimedStorageEventWorker, :zoekt_settings_enabled,
  feature_category: :global_search do
  let(:event) { Search::Zoekt::NodeWithNegativeUnclaimedStorageEvent.new(data: data) }

  let_it_be(:node) { create(:zoekt_node, :enough_free_space) }
  let_it_be(:index) { create(:zoekt_index, :ready, node: node) }
  let_it_be(:negative_node) { create(:zoekt_node, :enough_free_space) }
  let_it_be(:negative_index) do
    create(:zoekt_index, :ready, reserved_storage_bytes: negative_node.total_bytes * 2, node: negative_node)
  end

  let(:data) do
    { node_ids: [node.id, negative_node.id] }
  end

  it_behaves_like 'subscribes to event'

  it_behaves_like 'a Zoekt worker deferring on autovacuum of', [:zoekt_indices]

  context 'when Zoekt is not licensed or indexing is disabled' do
    before do
      allow(::Search::Zoekt).to receive(:licensed_and_indexing_enabled?).and_return(false)
    end

    it 'does nothing' do
      expect { consume_event(subscriber: described_class, event: event) }.not_to change { negative_index.reload.state }
    end
  end

  it 'has the `until_executed` deduplicate strategy' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
  end

  context 'when zoekt_negative_storage_eviction_best_fit is disabled' do
    before do
      stub_feature_flags(zoekt_negative_storage_eviction_best_fit: false)
    end

    it_behaves_like 'an idempotent worker' do
      context 'when node_ids is empty in the event data' do
        let(:data) do
          { node_ids: [] }
        end

        it 'does nothing' do
          expect(Search::Zoekt::Node).not_to receive(:negative_unclaimed_storage_bytes)

          expect { consume_event(subscriber: described_class, event: event) }
            .not_to publish_event(Search::Zoekt::IndexToEvictEvent)
        end
      end

      it 'processes nodes with negative unclaimed storage bytes' do
        expect_next_instance_of(described_class) do |instance|
          expect(instance).to receive(:log_extra_metadata_on_done).with(:indices_updated_count, 1)
        end

        expect { consume_event(subscriber: described_class, event: event) }
          .to change { negative_index.reload.state }.from('ready').to('pending_eviction')
          .and not_change { index.reload.state }
      end

      it 'processes in batches' do
        idx_2 = create(:zoekt_index, :ready, reserved_storage_bytes: negative_node.total_bytes * 2, node: negative_node)
        idx_3 = create(:zoekt_index, :ready, reserved_storage_bytes: negative_node.total_bytes * 2, node: negative_node)

        stub_const("#{described_class}::MAX_INDICES_TO_EVICT", 2)

        expect_next_instance_of(described_class) do |instance|
          expect(instance).to receive(:log_extra_metadata_on_done).with(:indices_updated_count, 2)
        end

        expect { consume_event(subscriber: described_class, event: event) }
          .to change { negative_index.reload.state }.from('ready').to('pending_eviction')
          .and change { idx_2.reload.state }.from('ready').to('pending_eviction')
          .and not_change { idx_3.reload.state }
          .and not_change { index.reload.state }

        expect_next_instance_of(described_class) do |instance|
          expect(instance).to receive(:log_extra_metadata_on_done).with(:indices_updated_count, 1)
        end

        expect { consume_event(subscriber: described_class, event: event) }
          .to change { idx_3.reload.state }.from('ready').to('pending_eviction')
      end
    end

    it 'evicts indices without reserved storage and keeps going until the bytes are freed' do
      zero_node = create(:zoekt_node, :enough_free_space)
      zero_index = create(:zoekt_index, :ready, reserved_storage_bytes: 0, node: zero_node)
      large_index = create(:zoekt_index, :ready, reserved_storage_bytes: zero_node.total_bytes * 2, node: zero_node)
      zero_event = Search::Zoekt::NodeWithNegativeUnclaimedStorageEvent.new(data: { node_ids: [zero_node.id] })

      expect { consume_event(subscriber: described_class, event: zero_event) }
        .to change { zero_index.reload.state }.from('ready').to('pending_eviction')
        .and change { large_index.reload.state }.from('ready').to('pending_eviction')
    end
  end

  context 'when zoekt_negative_storage_eviction_best_fit is enabled' do
    let(:data) { { node_ids: [negative_node.id] } }

    context 'when the disk is below the high watermark' do
      it 'skips the node' do
        logger = Search::Zoekt::Logger.build
        allow(Search::Zoekt::Logger).to receive(:build).and_return(logger)
        expect(logger).to receive(:info).with(hash_including(
          'message' => 'Skipping node with negative unclaimed storage bytes below the high watermark',
          'zoekt.node_id' => negative_node.id
        ))

        expect { consume_event(subscriber: described_class, event: event) }
          .not_to change { negative_index.reload.state }
      end
    end

    context 'when the disk is over the high watermark' do
      let_it_be_with_reload(:full_node) { create(:zoekt_node, :watermark_high) }
      let(:data) { { node_ids: [full_node.id] } }
      let(:usable) { full_node.usable_storage_bytes }

      def create_index(reserved_storage_bytes, state: :ready)
        create(:zoekt_index, state, reserved_storage_bytes: reserved_storage_bytes, node: full_node)
      end

      it 'evicts the smallest ready index that covers the shortfall' do
        # Shortfall: (10 + 6 + 1 + 3) / 16 - 1 = 4/16 of usable storage.
        largest = create_index(usable * 10 / 16)
        best_fit = create_index(usable * 6 / 16)
        too_small = create_index(usable / 16)
        not_ready = create_index(usable * 3 / 16, state: :in_progress)

        expect { consume_event(subscriber: described_class, event: event) }
          .to change { best_fit.reload.state }.from('ready').to('pending_eviction')
          .and not_change { largest.reload.state }
          .and not_change { too_small.reload.state }
          .and not_change { not_ready.reload.state }
      end

      it 'evicts the largest ready indices first when no single index covers the shortfall' do
        # Shortfall: (5 + 4.5 + 4 + 3) / 10 - 1 = 6.5/10 of usable storage.
        smallest = create_index(usable * 3 / 10)
        second = create_index(usable * 45 / 100)
        third = create_index(usable * 4 / 10)
        largest = create_index(usable * 5 / 10)

        expect_next_instance_of(described_class) do |instance|
          expect(instance).to receive(:log_extra_metadata_on_done).with(:indices_updated_count, 2)
        end

        expect { consume_event(subscriber: described_class, event: event) }
          .to change { largest.reload.state }.from('ready').to('pending_eviction')
          .and change { second.reload.state }.from('ready').to('pending_eviction')
          .and not_change { third.reload.state }
          .and not_change { smallest.reload.state }
      end
    end
  end
end
