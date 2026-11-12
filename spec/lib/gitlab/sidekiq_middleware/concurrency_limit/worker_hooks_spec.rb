# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::SidekiqMiddleware::ConcurrencyLimit::WorkerHooks, feature_category: :scalability do
  let(:worker_class) do
    Class.new do
      def self.name
        'TestHookWorker'
      end

      def self.on_concurrency_limit_deferred(args); end
      def self.on_concurrency_limit_resumed(args); end
    end
  end

  let(:job) { { 'args' => [1, 'a'] } }

  where(:entry_point, :hook) do
    [
      [:deferred, :on_concurrency_limit_deferred],
      [:resumed, :on_concurrency_limit_resumed]
    ]
  end

  with_them do
    subject(:call_hook) { described_class.public_send(entry_point, worker_class, job) }

    it 'calls the hook with the job arguments' do
      expect(worker_class).to receive(hook).with([1, 'a'])

      call_hook
    end

    context 'when the hook changes its arguments' do
      let(:job) { { 'args' => [1, { 'key' => 'value' }] } }

      it 'does not change the job arguments' do
        allow(worker_class).to receive(hook) do |args|
          args.last['key'] = 'changed'
          args << 'extra'
        end

        call_hook

        expect(job['args']).to eq([1, { 'key' => 'value' }])
      end
    end

    context 'when the arguments are compressed' do
      let(:job) do
        { 'args' => [1, 'a'] }.tap do |job|
          Gitlab::SidekiqMiddleware::SizeLimiter::Compressor.compress(job, Sidekiq.dump_json(job['args']))
        end
      end

      it 'calls the hook with the uncompressed arguments, leaving the job compressed' do
        expect(worker_class).to receive(hook).with([1, 'a'])

        call_hook

        expect(Gitlab::SidekiqMiddleware::SizeLimiter::Compressor.compressed?(job)).to be(true)
      end
    end

    context 'when the hook raises' do
      let(:error) { StandardError.new('boom') }

      it 'tracks the error' do
        allow(worker_class).to receive(hook).and_raise(error)

        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(error, worker_class: 'TestHookWorker', hook: hook)

        expect { call_hook }.not_to raise_error
      end
    end

    context 'when the worker has no hook' do
      let(:worker_class) { Class.new }

      it 'does nothing' do
        expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

        expect { call_hook }.not_to raise_error
      end
    end
  end
end
