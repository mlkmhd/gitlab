# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickHouse::ReadOnlyMarker, :click_house, feature_category: :database do
  let(:observed) { [] }

  before do
    allow(Gitlab::HTTP).to receive(:post).and_wrap_original do |original, *args|
      observed << described_class.active?
      original.call(*args)
    end
  end

  it 'is active during select' do
    ClickHouse::Client.select('SELECT 1', :main)

    expect(observed).to eq([true])
    expect(described_class.active?).to be(false)
  end

  it 'is not active during execute' do
    ClickHouse::Client.execute('SELECT 1', :main)

    expect(observed).to eq([false])
  end

  it 'restores the previous state when the query fails' do
    expect { ClickHouse::Client.select('SELECT broken(', :main) }
      .to raise_error(ClickHouse::Client::DatabaseError)

    expect(described_class.active?).to be(false)
  end
end
