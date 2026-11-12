# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Ci::Config::Interpolation::FunctionsStack, feature_category: :pipeline_composition do
  let(:functions) { ['truncate(0,4)', 'truncate(1,2)'] }
  let(:input_value) { 'test_input_value' }

  subject { described_class.new(functions, nil).evaluate(input_value) }

  it 'modifies the given input value according to the function expressions' do
    expect(subject).to be_success
    expect(subject.value).to eq('es')
  end

  context 'when applying a function fails' do
    let(:input_value) { 666 }

    it 'returns the error given by the failure' do
      expect(subject).not_to be_success
      expect(subject.errors).to contain_exactly(
        'error in `truncate` function: invalid input type: truncate can only be used with string inputs'
      )
    end
  end

  context 'when function expressions do not match any function' do
    let(:functions) { ['truncate(0)', 'unknown'] }

    it 'returns an error' do
      expect(subject).not_to be_success
      expect(subject.errors).to contain_exactly(
        'no function matching `truncate(0)`: check that the function name, arguments, and types are correct',
        'no function matching `unknown`: check that the function name, arguments, and types are correct'
      )
    end
  end

  context 'when split is the last function' do
    let(:functions) { ["split(',')"] }
    let(:input_value) { 'a,b,c' }

    it 'splits the input string into an array' do
      expect(subject).to be_success
      expect(subject.value).to eq(%w[a b c])
    end
  end

  context 'when split is not the last function in the chain' do
    let(:functions) { ["split(',')", 'truncate(0,1)'] }
    let(:input_value) { 'a,b,c' }

    it 'returns an error' do
      expect(subject).not_to be_success
      expect(subject.errors).to contain_exactly(
        'split() must be the last function in a chain (it returns an array, not a string)'
      )
    end
  end

  context 'with the default function' do
    let(:ctx) do
      Gitlab::Ci::Config::Interpolation::Context.fabricate({ component: { version: nil, sha: 'abc123def' } })
    end

    let(:input_value) { nil }

    subject { described_class.new(functions, ctx).evaluate(input_value) }

    before do
      allow(Gitlab::Ci::Config::FeatureFlags).to receive(:enabled?)
        .with(:ci_interpolation_default_function)
        .and_return(true)
    end

    context 'when chained with another default' do
      let(:functions) { ['default(component.version)', "default('latest')"] }

      it 'falls back to the next default' do
        expect(subject).to be_success
        expect(subject.value).to eq('latest')
      end
    end

    context 'when followed by a string function' do
      let(:functions) { ['default(component.sha)', 'truncate(0,3)'] }

      it 'passes the fallback to the next function' do
        expect(subject).to be_success
        expect(subject.value).to eq('abc')
      end
    end

    context 'when a string function comes before default' do
      let(:functions) { ['truncate(0,3)', 'default(component.sha)'] }

      it 'fails on the nil value before default runs' do
        expect(subject).not_to be_success
        expect(subject.errors).to contain_exactly(
          'error in `truncate` function: invalid input type: truncate can only be used with string inputs'
        )
      end
    end

    context 'with invalid syntax' do
      using RSpec::Parameterized::TableSyntax

      where(:expression) do
        [
          'default component.sha',
          'default()',
          'default("latest")',
          "default('a', 'b')",
          'default( component.sha )',
          'default(component.sha',
          'defaults(component.sha)',
          "default('it's')"
        ]
      end

      with_them do
        let(:functions) { [expression] }

        it 'returns an error naming the expression' do
          expect(subject).not_to be_success
          expect(subject.errors).to contain_exactly(
            "no function matching `#{expression}`: check that the function name, arguments, and types are correct"
          )
        end
      end
    end

    context 'when the access argument is not in the context' do
      let(:functions) { ['default(component.reference)'] }

      it 'returns an error' do
        expect(subject).not_to be_success
        expect(subject.errors).to contain_exactly(
          'error in `default` function: invalid argument: ' \
            'unknown interpolation provided: `reference` in `component.reference`'
        )
      end
    end

    context 'when an access argument error is followed by another function' do
      let(:functions) { ['default(component.unknown)', 'truncate(0,3)'] }

      it 'returns only the default error' do
        expect(subject).not_to be_success
        expect(subject.errors).to contain_exactly(
          'error in `default` function: invalid argument: ' \
            'unknown interpolation provided: `unknown` in `component.unknown`'
        )
      end
    end

    context 'when ci_interpolation_default_function feature flag is disabled' do
      let(:functions) { ['default(component.sha)'] }

      before do
        allow(Gitlab::Ci::Config::FeatureFlags).to receive(:enabled?)
          .with(:ci_interpolation_default_function)
          .and_return(false)
      end

      it 'returns an error' do
        expect(subject).not_to be_success
        expect(subject.errors).to contain_exactly(
          'no function matching `default(component.sha)`: ' \
            'check that the function name, arguments, and types are correct'
        )
      end
    end
  end
end
