# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Database::LockRecorder, feature_category: :database do
  let(:recorder) { described_class.new }
  let(:record) { build_stubbed(:user) }

  describe '.instance' do
    around do |example|
      previous = Thread.current[:lock_recorder]
      Thread.current[:lock_recorder] = nil
      example.run
    ensure
      Thread.current[:lock_recorder] = previous
    end

    it 'memoizes a single instance per thread', :aggregate_failures do
      instance = described_class.instance

      expect(instance).to be_an_instance_of(described_class)
      expect(described_class.instance).to be(instance)
    end

    it 'does not share the instance across threads' do
      instance = described_class.instance
      other_instance = Thread.new { described_class.instance }.value

      expect(other_instance).not_to be(instance)
    end
  end

  describe '.record_key' do
    it 'returns the table name and the record id' do
      expect(described_class.record_key(record)).to eq([record.class.table_name, record.id])
    end
  end

  describe '#locks' do
    it 'defaults to an empty hash' do
      expect(recorder.locks).to eq({})
    end

    it 'returns the same hash on subsequent calls' do
      locks = recorder.locks

      expect(recorder.locks).to be(locks)
    end
  end

  describe '#add' do
    it 'records the lock type keyed by the record key' do
      recorder.add(record, 'FOR UPDATE')

      expect(recorder.locks).to eq({ described_class.record_key(record) => 'FOR UPDATE' })
    end

    it 'overwrites the lock type for an already recorded record' do
      recorder.add(record, 'FOR SHARE')
      recorder.add(record, 'FOR UPDATE')

      expect(recorder.locks).to eq({ described_class.record_key(record) => 'FOR UPDATE' })
    end

    it 'records each record separately' do
      other_record = build_stubbed(:user)

      recorder.add(record, 'FOR UPDATE')
      recorder.add(other_record, 'FOR SHARE')

      expect(recorder.locks).to eq({
        described_class.record_key(record) => 'FOR UPDATE',
        described_class.record_key(other_record) => 'FOR SHARE'
      })
    end
  end

  describe '#recording?' do
    it 'is false before recording starts' do
      expect(recorder).not_to be_recording
    end

    it 'is true after #start' do
      recorder.start

      expect(recorder).to be_recording
    end

    it 'is false after #stop' do
      recorder.start
      recorder.stop

      expect(recorder).not_to be_recording
    end
  end

  describe '#clear' do
    it 'removes all recorded locks' do
      recorder.add(record, 'FOR UPDATE')

      recorder.clear

      expect(recorder.locks).to be_empty
    end

    it 'does not stop the recording' do
      recorder.start

      recorder.clear

      expect(recorder).to be_recording
    end
  end
end
