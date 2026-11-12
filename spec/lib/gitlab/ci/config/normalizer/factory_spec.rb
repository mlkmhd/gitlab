# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Ci::Config::Normalizer::Factory, feature_category: :pipeline_composition do
  describe '#create' do
    context 'when no strategy applies' do
      subject { described_class.new(nil, nil).create } # rubocop:disable Rails/SaveBang -- not an ActiveRecord method

      it { is_expected.to be_empty }
    end
  end
end
