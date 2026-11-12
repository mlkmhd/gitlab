# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::SidekiqMiddleware::ConcurrencyLimit::Scope, feature_category: :security_policy_management do
  using RSpec::Parameterized::TableSyntax

  let(:scope_type) { :root_namespace }
  let(:max_percentage) { 0.25 }
  let(:limit) { nil }
  let(:worker_class) do
    type = scope_type
    percentage = max_percentage
    absolute = limit

    Class.new do
      def self.name
        'TestScopedConcurrencyLimitWorker'
      end

      include ApplicationWorker

      concurrency_limit_scope(type, enabled: -> { true }, max_percentage: percentage, limit: absolute)
    end
  end

  subject(:scope) { described_class.for(worker_class) }

  before do
    stub_feature_flags(disable_sidekiq_concurrency_limit_scope_TestScopedConcurrencyLimitWorker: false)
  end

  describe '.for' do
    it 'builds the scope declared by the worker' do
      expect(scope).to be_a(described_class)
      expect(scope.type).to eq(:root_namespace)
    end

    context 'when the worker declares no scope' do
      let(:worker_class) do
        Class.new do
          def self.name
            'TestUnscopedWorker'
          end

          include ApplicationWorker
        end
      end

      it { is_expected.to be_nil }
    end

    context 'when the class is not a worker' do
      let(:worker_class) { Class.new }

      it { is_expected.to be_nil }
    end

    context 'when the scope is not enabled' do
      before do
        allow(worker_class.get_concurrency_limit_scope[:enabled]).to receive(:call).and_return(false)
      end

      it { is_expected.to be_nil }
    end

    context 'when the worker declares no enabled lambda' do
      let(:worker_class) do
        Class.new do
          def self.name
            'TestScopedConcurrencyLimitWorker'
          end

          include ApplicationWorker

          concurrency_limit_scope(:user, limit: -> { 2 })
        end
      end

      it { is_expected.to be_a(described_class) }
    end

    context 'with only a limit' do
      let(:max_percentage) { nil }

      where(:limit, :scoped) do
        -> { 2 }   | true
        -> { 0 }   | false
        -> { -1 }  | false
        -> { nil } | false
      end

      with_them do
        it { expect(scope.present?).to eq(scoped) }
      end
    end

    context 'with a max_percentage and a limit of 0' do
      let(:limit) { -> { 0 } }

      it { is_expected.to be_a(described_class) }
    end

    context 'when sidekiq_concurrency_limit_scope is disabled' do
      before do
        stub_feature_flags(sidekiq_concurrency_limit_scope: false)
      end

      it { is_expected.to be_nil }
    end

    context 'when the scope is disabled for the worker' do
      before do
        stub_feature_flags(disable_sidekiq_concurrency_limit_scope_TestScopedConcurrencyLimitWorker: true)
      end

      it { is_expected.to be_nil }
    end

    context 'when sidekiq_concurrency_limit_middleware is disabled' do
      before do
        stub_feature_flags(sidekiq_concurrency_limit_middleware: false)
      end

      it { is_expected.to be_nil }
    end
  end

  describe '#key_for' do
    let(:job) { { 'args' => [1], 'meta.root_namespace' => 'my-top-group', 'meta.gl_user_id' => 7 } }

    subject(:key) { scope.key_for(job) }

    where(:scope_type, :expected_key) do
      :root_namespace | 'root_namespace:my-top-group'
      :user           | 'user:7'
    end

    with_them do
      it { is_expected.to eq(expected_key) }

      context 'without the tenant in the job context' do
        let(:job) { { 'args' => [1], 'meta.root_namespace' => '', 'meta.gl_user_id' => nil } }

        it { is_expected.to be_nil }
      end
    end
  end

  describe '#limit_for' do
    subject(:scope_limit) { scope.limit_for(worker_limit) }

    where(:max_percentage, :limit, :worker_limit, :expected_limit) do
      0.25 | nil       | 0  | 0
      0.25 | nil       | -1 | 0
      0.25 | nil       | 1  | 1
      0.25 | nil       | 10 | 3
      nil  | -> { 4 }  | 10 | 4
      0.25 | -> { 0 }  | 10 | 3
      0.25 | -> { 2 }  | 10 | 2
      0.25 | -> { 50 } | 10 | 3
      0.25 | -> { 2 }  | 0  | 0
    end

    with_them do
      it { is_expected.to eq(expected_limit) }
    end
  end
end
