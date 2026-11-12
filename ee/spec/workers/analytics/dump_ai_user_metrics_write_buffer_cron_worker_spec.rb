# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::DumpAiUserMetricsWriteBufferCronWorker, :clean_gitlab_redis_shared_state, feature_category: :value_stream_management do
  let(:job) { described_class.new }
  let(:perform) { job.perform }

  let_it_be(:user) { create(:user) }
  let_it_be(:user2) { create(:user) }
  let_it_be(:user3) { create(:user) }

  let(:inserted_records) { Ai::UserMetrics.all.map(&:attributes) }

  describe "#perform", :freeze_time do
    it 'does not insert anything' do
      perform

      expect(inserted_records).to be_empty
    end

    context "when buffer has data" do
      before do
        Ai::UserMetrics.write_buffer.add({ user_id: user.id, last_duo_activity_on: 1.day.ago.to_date })
        Ai::UserMetrics.write_buffer.add({ user_id: user2.id, last_duo_activity_on: 2.days.ago.to_date })
        Ai::UserMetrics.write_buffer.add({ user_id: user3.id, last_duo_activity_on: 3.days.ago.to_date })
      end

      it 'upserts all rows' do
        status = perform

        expect(status).to eq({ status: :processed, inserted_rows: 3 })
        expect(inserted_records).to match_array([
          hash_including('user_id' => user.id, 'last_duo_activity_on' => 1.day.ago.to_date),
          hash_including('user_id' => user2.id, 'last_duo_activity_on' => 2.days.ago.to_date),
          hash_including('user_id' => user3.id, 'last_duo_activity_on' => 3.days.ago.to_date)
        ])
      end

      context 'when DB has preexisting data' do
        before do
          Ai::UserMetrics.create!(user_id: user.id, last_duo_activity_on: 10.days.ago.to_date)
          Ai::UserMetrics.create!(user_id: user2.id, last_duo_activity_on: 11.days.ago.to_date)
          Ai::UserMetrics.create!(user_id: user3.id, last_duo_activity_on: 1.minute.ago.to_date)
        end

        it 'updates all rows with older last_duo_activity_on' do
          status = perform

          expect(status).to eq({ status: :processed, inserted_rows: 3 })
          expect(inserted_records).to match_array([
            hash_including('user_id' => user.id, 'last_duo_activity_on' => 1.day.ago.to_date),
            hash_including('user_id' => user2.id, 'last_duo_activity_on' => 2.days.ago.to_date),
            hash_including('user_id' => user3.id, 'last_duo_activity_on' => 1.minute.ago.to_date)
          ])
        end
      end

      context 'when looping twice' do
        it 'upserts all rows' do
          stub_const("#{described_class.name}::BATCH_SIZE", 2)

          expect(perform).to eq({ status: :processed, inserted_rows: 3 })
        end
      end

      it 'reports the pending rows before draining' do
        expect(job).to receive(:log_extra_metadata_on_done).with(:pending_rows, 3)
        expect(job).to receive(:log_extra_metadata_on_done).with(:result, anything)

        perform
      end

      context 'when the upsert fails' do
        let(:error) { ActiveRecord::StatementInvalid.new('boom') }

        before do
          allow(Ai::UserMetrics).to receive(:upsert_all).and_raise(error)
        end

        it 'puts the batch back and raises the original error' do
          expect(Ai::UserMetrics.write_buffer).to receive(:requeue).once.and_call_original
          expect(Ai::UserMetrics.write_buffer).not_to receive(:add)

          expect { perform }.to raise_error(error)

          expect(Ai::UserMetrics.write_buffer.pending).to eq(3)
          expect(Ai::UserMetrics.write_buffer.pop(3).map { |row| row['user_id'] })
            .to contain_exactly(user.id, user2.id, user3.id)
          expect(inserted_records).to be_empty
        end
      end

      context 'when time limit is up' do
        it 'returns over_time status' do
          stub_const("#{described_class.name}::BATCH_SIZE", 1)

          allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
            allow(limiter).to receive(:over_time?).and_return(false, true)
          end

          status = perform

          expect(status).to eq({ status: :over_time, inserted_rows: 2 })
          expect(inserted_records).to match([
            hash_including('user_id' => user.id, 'last_duo_activity_on' => 1.day.ago.to_date),
            hash_including('user_id' => user2.id, 'last_duo_activity_on' => 2.days.ago.to_date)
          ])
        end
      end
    end
  end
end
