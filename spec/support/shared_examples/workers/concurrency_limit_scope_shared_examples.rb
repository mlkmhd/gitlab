# frozen_string_literal: true

RSpec.shared_examples 'a worker with a concurrency limit scope' do |type:, max_percentage:, feature_flag:|
  let(:scope) { Gitlab::SidekiqMiddleware::ConcurrencyLimit::Scope.for(described_class) }

  before do
    # Unstubbed flags are enabled in specs, so the per-worker kill switch is on until stubbed off.
    stub_feature_flags("disable_sidekiq_concurrency_limit_scope_#{described_class.name}": false)
  end

  it "caps each #{type} at #{(max_percentage * 100).round}% of the worker limit" do
    expect(scope.type).to eq(type)
    expect(scope.limit_for(100)).to eq((100 * max_percentage).ceil)
  end

  context 'when the worker kill switch is enabled' do
    before do
      stub_feature_flags("disable_sidekiq_concurrency_limit_scope_#{described_class.name}": true)
    end

    it 'does not scope the worker' do
      expect(scope).to be_nil
    end
  end

  context "when the #{feature_flag} flag is disabled" do
    before do
      stub_feature_flags(feature_flag => false)
    end

    it 'does not scope the worker' do
      expect(scope).to be_nil
    end
  end
end
