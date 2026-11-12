# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Duo::CodeReview::Availability::Base, feature_category: :dap_code_review do
  using RSpec::Parameterized::TableSyntax

  # rubocop:disable RSpec/VerifiedDoubles -- any container type works
  let(:container) do
    double(duo_features_enabled: duo_features_enabled, duo_foundational_flows_enabled: foundational_flows_enabled)
  end
  # rubocop:enable RSpec/VerifiedDoubles

  let(:duo_features_enabled) { true }
  let(:foundational_flows_enabled) { true }

  describe 'methods that subclasses must define' do
    where(:method_name) { %i[available? decisions_settings_available? depth_settings_available?] }

    with_them do
      it 'raises NotImplementedError' do
        expect { described_class.new(container).public_send(method_name) }.to raise_error(NotImplementedError)
      end
    end
  end

  describe '#check_duo_features' do
    let(:availability_class) do
      Class.new(described_class) do
        attr_accessor :beta_enabled

        def check(...)
          check_duo_features(...)
        end

        private

        def duo_beta_features_enabled?
          beta_enabled
        end
      end
    end

    let(:availability) { availability_class.new(container).tap { |a| a.beta_enabled = beta_enabled } }

    context 'when the subclass does not define the beta features check' do
      let(:availability_class) do
        Class.new(described_class) do
          def check(...)
            check_duo_features(...)
          end
        end
      end

      it 'raises NotImplementedError for beta checks' do
        expect { availability_class.new(container).check(beta: true) }.to raise_error(NotImplementedError)
      end
    end

    where(:duo_features_enabled, :foundational_flows_enabled, :beta_enabled, :options, :expected) do
      false | true  | true  | {}                                        | false
      true  | true  | false | {}                                        | true
      true  | false | false | {}                                        | false
      true  | false | false | { foundational_flows: false }             | true
      true  | true  | false | { beta: true }                            | false
      true  | true  | true  | { beta: true }                            | true
      true  | false | true  | { beta: true, foundational_flows: false } | true
    end

    with_them do
      it 'returns the block result when all checks pass' do
        expect(availability.check(**options) { true }).to be(expected)
      end

      it 'returns the check result without a block' do
        expect(availability.check(**options)).to be(expected)
      end
    end

    context 'when the checks pass' do
      let(:availability) { availability_class.new(container) }

      it 'returns the block result' do
        expect(availability.check { false }).to be(false)
      end
    end
  end
end
