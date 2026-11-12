# frozen_string_literal: true

require 'fast_spec_helper'
require 'active_record'

RSpec.describe Gitlab::Database::SqlRuntime, feature_category: :database do
  let(:registry) { ActiveRecord::RuntimeRegistry }

  describe '.total_ms' do
    it 'reads the accumulated SQL runtime on the Rails version in use' do
      expect(described_class.total_ms).to be_a(Numeric)
    end

    context 'when on Rails 8.1 or later' do
      # Stats is built here rather than doubled, so the example also runs on
      # Rails 8.0, where RuntimeRegistry.stats does not exist.
      let(:stats) { Struct.new(:sql_runtime).new(12.5) }

      before do
        allow(ActiveRecord).to receive(:gem_version).and_return(Gem::Version.new('8.1.0'))
      end

      it 'reads the runtime from stats' do
        without_partial_double_verification do
          allow(registry).to receive(:stats).and_return(stats)
        end

        expect(described_class.total_ms).to eq(12.5)
      end
    end

    context 'when on a Rails version before 8.1' do
      before do
        allow(ActiveRecord).to receive(:gem_version).and_return(Gem::Version.new('8.0.0'))
      end

      it 'reads the runtime from the registry' do
        without_partial_double_verification do
          allow(registry).to receive(:sql_runtime).and_return(7.5)
        end

        expect(described_class.total_ms).to eq(7.5)
      end
    end
  end
end
