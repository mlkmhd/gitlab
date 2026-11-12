# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::ValidityChecks::RawTokenBatch, feature_category: :secret_detection do
  let(:tokens) do
    [
      { 'id' => '1', 'token_type' => 'pat', 'raw_token' => 'glpat-a' },
      { id: '2', token_type: 'pat', raw_token: 'glpat-a' },
      { id: '3', token_type: 'anthropic_key', raw_token: 'sk-ant' }
    ]
  end

  subject(:batch) { described_class.new(tokens) }

  it 'groups distinct raw values by type, whatever the key style' do
    expect(batch.by_type).to eq('pat' => ['glpat-a'], 'anthropic_key' => ['sk-ant'])
  end

  it "maps the verifiers' answers back to every id without the raw value" do
    statuses = { 'pat' => { 'glpat-a' => { status: 'active' } }, 'anthropic_key' => { 'sk-ant' => { error: 'x' } } }

    expect(batch.results(statuses)).to eq([
      { id: '1', token_type: 'pat', status: 'active' },
      { id: '2', token_type: 'pat', status: 'active' },
      { id: '3', token_type: 'anthropic_key', error: 'x' }
    ])
  end
end
