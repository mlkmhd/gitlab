# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Observability::GroupO11ySetting, feature_category: :observability do
  describe '.hosted_service?' do
    context 'when the observability hosted service is available', :saas_observability_hosted_service do
      it 'is true' do
        expect(described_class.hosted_service?).to be(true)
      end
    end

    context 'when the observability hosted service is not available' do
      it 'is false' do
        expect(described_class.hosted_service?).to be(false)
      end
    end
  end
end
