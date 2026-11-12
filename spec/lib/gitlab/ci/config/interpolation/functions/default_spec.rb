# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Ci::Config::Interpolation::Functions::Default, feature_category: :pipeline_composition do
  using RSpec::Parameterized::TableSyntax

  let(:ctx) do
    Gitlab::Ci::Config::Interpolation::Context.fabricate({
      inputs: { tags: %w[a b] },
      component: { version: nil, sha: 'abc123' }
    })
  end

  subject(:function) { described_class.new(function_expression, ctx) }

  describe '.matches?' do
    where(:function_expression, :matches) do
      "default('latest')"       | true
      "default('')"             | true
      "default('a b')"          | true
      'default(component.sha)'  | true
      'default(inputs.list[0])' | true
      'default(inputs.my-key)'  | true
      "default( 'latest' )"     | false
      'default( component.sha)' | false
      'default'                 | false
      'default()'               | false
      'default component.sha'   | false
      'default("latest")'       | false
      "default('a', 'b')"       | false
      'default(component.sha'   | false
      'defaults(component.sha)' | false
    end

    with_them do
      it { expect(described_class.matches?(function_expression)).to be(matches) }
    end
  end

  describe '#execute' do
    let(:function_expression) { 'default(component.sha)' }

    where(:input_value, :expected_output) do
      nil      | 'abc123'
      ''       | 'abc123'
      'v1.0.0' | 'v1.0.0'
      ' '      | ' '
      false    | false
      0        | 0
      []       | []
    end

    with_them do
      it 'returns the fallback only for nil or an empty string', :aggregate_failures do
        expect(function.execute(input_value)).to eq(expected_output)
        expect(function).to be_valid
      end
    end

    context 'with a literal argument' do
      let(:function_expression) { "default('latest')" }

      it 'returns the literal' do
        expect(function.execute(nil)).to eq('latest')
      end
    end

    context 'with an access argument that resolves to a non-string value' do
      let(:function_expression) { 'default(inputs.tags)' }

      it 'returns the value with its type' do
        expect(function.execute(nil)).to eq(%w[a b])
      end
    end

    context 'with an access argument that resolves to nil' do
      let(:function_expression) { 'default(component.version)' }

      it 'returns nil' do
        expect(function.execute('')).to be_nil
        expect(function).to be_valid
      end
    end

    context 'with an access argument that does not exist' do
      let(:function_expression) { 'default(component.unknown)' }

      it 'returns an error', :aggregate_failures do
        expect(function.execute(nil)).to be_nil
        expect(function.errors).to contain_exactly(
          'error in `default` function: invalid argument: ' \
            'unknown interpolation provided: `unknown` in `component.unknown`'
        )
      end
    end

    # Typed literals are not supported: an unquoted value is read as an access.
    context 'with an access argument without a context name' do
      where(:function_expression) { ['default(sha)', 'default(true)', 'default(false)', 'default(1)'] }

      with_them do
        it 'returns an error' do
          function.execute(nil)

          expect(function.errors).to contain_exactly(
            'error in `default` function: invalid argument: ' \
              'invalid pattern used for interpolation. valid pattern is $[[ inputs.input ]]'
          )
        end
      end
    end

    context 'with an access argument that does not exist and a present value' do
      let(:function_expression) { 'default(component.unknown)' }

      it 'still returns an error' do
        expect(function.execute('v1.0.0')).to be_nil
        expect(function).not_to be_valid
      end
    end
  end
end
