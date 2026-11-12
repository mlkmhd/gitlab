# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ci::Variables::Collection, feature_category: :pipeline_composition do
  describe '.fabricate' do
    using RSpec::Parameterized::TableSyntax

    where do
      {
        "given an array of variables": {
          input: [
            { key: 'VAR1', value: 'value1' },
            { key: 'VAR2', value: 'value2' }
          ]
        },
        "given a hash of variables": {
          input: { 'VAR1' => 'value1', 'VAR2' => 'value2' }
        },
        "given a proc that evaluates to an array": {
          input: -> do
            [
              { key: 'VAR1', value: 'value1' },
              { key: 'VAR2', value: 'value2' }
            ]
          end
        },
        "given a proc that evaluates to a hash": {
          input: -> do
            { 'VAR1' => 'value1', 'VAR2' => 'value2' }
          end
        },
        "given a collection": {
          input: Gitlab::Ci::Variables::Collection.new(
            [
              { key: 'VAR1', value: 'value1' },
              { key: 'VAR2', value: 'value2' }
            ]
          )
        }
      }
    end

    with_them do
      subject(:collection) { Gitlab::Ci::Variables::Collection.fabricate(input) }

      it 'returns a collection' do
        expect(collection).to be_a(Gitlab::Ci::Variables::Collection)
        expect(collection.size).to eq(2)
        expect(collection.map(&:key)).to contain_exactly('VAR1', 'VAR2')
        expect(collection.map(&:value)).to contain_exactly('value1', 'value2')
      end
    end

    context 'when given an unrecognized type' do
      it 'raises error' do
        expect { described_class.fabricate(1) }.to raise_error(ArgumentError)
      end
    end
  end

  describe '.new' do
    it 'can be initialized with an array' do
      variable = { key: 'VAR', value: 'value', public: true, masked: false }

      collection = described_class.new([variable])

      expect(collection.first.to_runner_variable).to eq variable
    end

    it 'can be initialized without an argument' do
      is_expected.to be_none
    end

    it 'reuses Item objects when initialized with Items' do
      item = Gitlab::Ci::Variables::Collection::Item.new(key: 'VAR', value: 'value')

      collection = described_class.new([item])

      expect(collection.first.object_id).to eq item.object_id
    end
  end

  describe '#append' do
    it 'appends a hash' do
      subject.append(key: 'VARIABLE', value: 'something')

      is_expected.to be_one
    end

    it 'appends a Ci::Variable' do
      subject.append(build(:ci_variable))

      is_expected.to be_one
    end

    it 'appends an internal resource' do
      collection = described_class.new([{ key: 'TEST', value: '1' }])

      subject.append(collection.first)

      is_expected.to be_one
    end

    it 'returns self' do
      expect(subject.append(key: 'VAR', value: 'test'))
        .to eq subject
    end
  end

  describe '#compact' do
    subject do
      described_class.new
        .append(key: 'STRING', value: 'string')
        .append(key: 'NIL', value: nil)
        .append(key: nil, value: 'string')
    end

    it 'returns a new Collection instance', :aggregate_failures do
      collection = subject.compact

      expect(collection).to be_an_instance_of(described_class)
      expect(collection).not_to eql(subject)
    end

    it 'rejects pair that has nil value', :aggregate_failures do
      collection = subject.compact

      expect(collection).not_to include(key: 'NIL', value: nil, public: true)
      expect(collection).to include(key: 'STRING', value: 'string', public: true)
      expect(collection).to include(key: nil, value: 'string', public: true)
    end
  end

  describe '#concat' do
    it 'appends all elements from an array' do
      collection = described_class.new([{ key: 'VAR_1', value: '1' }])
      variables = [{ key: 'VAR_2', value: '2' }, { key: 'VAR_3', value: '3' }]

      collection.concat(variables)

      expect(collection).to include(key: 'VAR_1', value: '1', public: true)
      expect(collection).to include(key: 'VAR_2', value: '2', public: true)
      expect(collection).to include(key: 'VAR_3', value: '3', public: true)
    end

    it 'appends all elements from other collection' do
      collection = described_class.new([{ key: 'VAR_1', value: '1' }])
      additional = described_class.new([
        { key: 'VAR_2', value: '2' },
        { key: 'VAR_3', value: '3' }
      ])

      collection.concat(additional)

      expect(collection).to include(key: 'VAR_1', value: '1', public: true)
      expect(collection).to include(key: 'VAR_2', value: '2', public: true)
      expect(collection).to include(key: 'VAR_3', value: '3', public: true)
    end

    it 'does not concatenate resource if it undefined' do
      collection = described_class.new([{ key: 'VAR_1', value: '1' }])

      collection.concat(nil)

      expect(collection).to be_one
    end

    it 'returns self' do
      expect(subject.concat([key: 'VAR', value: 'test']))
        .to eq subject
    end

    it 'reuses Item objects when concatenating a Collection' do
      source = described_class.new([{ key: 'VAR', value: '1' }])
      target = described_class.new

      target.concat(source)

      expect(target.first.object_id).to eq source.first.object_id
    end
  end

  describe '#+' do
    it 'makes it possible to combine with an array' do
      collection = described_class.new([{ key: 'TEST', value: '1' }])
      variables = [{ key: 'TEST', value: 'something' }]

      expect((collection + variables).count).to eq 2
    end

    it 'makes it possible to combine with another collection' do
      collection = described_class.new([{ key: 'TEST', value: '1' }])
      other = described_class.new([{ key: 'TEST', value: '2' }])

      expect((collection + other).count).to eq 2
    end

    it 'reuses Item objects from both collections' do
      col1 = described_class.new([{ key: 'VAR1', value: '1' }])
      col2 = described_class.new([{ key: 'VAR2', value: '2' }])

      result = col1 + col2

      expect(result.first.object_id).to eq col1.first.object_id
      expect(result.to_a.last.object_id).to eq col2.first.object_id
    end
  end

  describe '#[]' do
    subject { described_class.new(variables)[var_name] }

    shared_examples 'an array access operator' do
      context 'for a non-existent variable name' do
        let(:var_name) { 'UNKNOWN_VAR' }

        it 'returns nil' do
          is_expected.to be_nil
        end
      end

      context 'for an existent variable name' do
        let(:var_name) { 'VAR' }

        it 'returns the last Item' do
          is_expected.to be_an_instance_of(Gitlab::Ci::Variables::Collection::Item)
          expect(subject.to_runner_variable).to eq(variables.last)
        end
      end
    end

    context 'with variable key with single entry' do
      let(:variables) do
        [
          { key: 'VAR', value: 'value', public: true, masked: false }
        ]
      end

      it_behaves_like 'an array access operator'
    end

    context 'with variable key with multiple entries' do
      let(:variables) do
        [
          { key: 'VAR', value: 'value', public: true, masked: false },
          { key: 'VAR', value: 'override value', public: true, masked: false }
        ]
      end

      it_behaves_like 'an array access operator'
    end
  end

  describe '#all' do
    subject { described_class.new(variables).all(var_name) }

    shared_examples 'a method returning all known variables or nil' do
      context 'for a non-existent variable name' do
        let(:var_name) { 'UNKNOWN_VAR' }

        it 'returns nil' do
          is_expected.to be_nil
        end
      end

      context 'for an existing variable name' do
        let(:var_name) { 'VAR' }

        it 'returns all expected Items' do
          is_expected.to eq(expected_variables.map { |v| Gitlab::Ci::Variables::Collection::Item.fabricate(v) })
        end
      end
    end

    context 'with variable key with single entry' do
      let(:variables) do
        [
          { key: 'VAR', value: 'value', public: true, masked: false }
        ]
      end

      it_behaves_like 'a method returning all known variables or nil' do
        let(:expected_variables) do
          [
            { key: 'VAR', value: 'value', public: true, masked: false }
          ]
        end
      end
    end

    context 'with variable key with multiple entries' do
      let(:variables) do
        [
          { key: 'VAR', value: 'value', public: true, masked: false },
          { key: 'VAR', value: 'override value', public: true, masked: false }
        ]
      end

      it_behaves_like 'a method returning all known variables or nil' do
        let(:expected_variables) do
          [
            { key: 'VAR', value: 'value', public: true, masked: false },
            { key: 'VAR', value: 'override value', public: true, masked: false }
          ]
        end
      end
    end
  end

  describe '#size' do
    it 'returns zero for empty collection' do
      collection = described_class.new([])

      expect(collection.size).to eq(0)
    end

    it 'returns 2 for collection with 2 variables' do
      collection = described_class.new(
        [
          { key: 'VAR1', value: 'value', public: true, masked: false },
          { key: 'VAR2', value: 'value', public: true, masked: false }
        ])

      expect(collection.size).to eq(2)
    end

    it 'returns 3 for collection with 2 duplicate variables' do
      collection = described_class.new(
        [
          { key: 'VAR1', value: 'value', public: true, masked: false },
          { key: 'VAR2', value: 'value', public: true, masked: false },
          { key: 'VAR1', value: 'value', public: true, masked: false }
        ])

      expect(collection.size).to eq(3)
    end
  end

  describe '#to_runner_variables' do
    it 'creates an array of hashes in a runner-compatible format' do
      collection = described_class.new([{ key: 'TEST', value: '1' }])

      expect(collection.to_runner_variables)
        .to eq [{ key: 'TEST', value: '1', public: true, masked: false }]
    end
  end

  describe '#to_hash' do
    it 'returns regular hash in valid order without duplicates' do
      collection = described_class.new
        .append(key: 'TEST1', value: 'test-1')
        .append(key: 'TEST2', value: 'test-2')
        .append(key: 'TEST1', value: 'test-3')

      expect(collection.to_hash).to eq('TEST1' => 'test-3', 'TEST2' => 'test-2')

      expect(collection.to_hash).to include(TEST1: 'test-3')
      expect(collection.to_hash).not_to include(TEST1: 'test-1')
    end
  end

  describe '#reject' do
    let(:collection) do
      described_class.new
        .append(key: 'CI_JOB_NAME', value: 'test-1')
        .append(key: 'CI_BUILD_ID', value: '1')
        .append(key: 'TEST1', value: 'test-3')
    end

    subject { collection.reject { |var| var[:key] =~ /\ACI_(JOB|BUILD)/ } }

    it 'returns a Collection instance' do
      is_expected.to be_an_instance_of(described_class)
    end

    it 'returns correctly filtered Collection' do
      comp = collection.to_runner_variables.reject { |var| var[:key] =~ /\ACI_(JOB|BUILD)/ }
      expect(subject.to_runner_variables).to eq(comp)
    end
  end

  describe '#sort_and_expand_all' do
    context 'table tests' do
      using RSpec::Parameterized::TableSyntax

      where do
        {
          "empty array": {
            variables: [],
            keep_undefined: false,
            result: []
          },
          "empty string": {
            variables: [
              { key: 'variable', value: '' }
            ],
            result: [
              { key: 'variable', value: '' }
            ]
          },
          "simple expansions": {
            variables: [
              { key: 'variable', value: 'value' },
              { key: 'variable2', value: 'result' },
              { key: 'variable3', value: 'key$variable$variable2' },
              { key: 'variable4', value: 'key$variable$variable3' }
            ],
            keep_undefined: false,
            result: [
              { key: 'variable', value: 'value' },
              { key: 'variable2', value: 'result' },
              { key: 'variable3', value: 'keyvalueresult' },
              { key: 'variable4', value: 'keyvaluekeyvalueresult' }
            ]
          },
          "complex expansion": {
            variables: [
              { key: 'variable', value: 'value' },
              { key: 'variable2', value: 'key${variable}' }
            ],
            keep_undefined: false,
            result: [
              { key: 'variable', value: 'value' },
              { key: 'variable2', value: 'keyvalue' }
            ]
          },
          "unused variables": {
            variables: [
              { key: 'variable', value: 'value' },
              { key: 'variable2', value: 'result2' },
              { key: 'variable3', value: 'result3' },
              { key: 'variable4', value: 'key$variable$variable3' }
            ],
            keep_undefined: false,
            result: [
              { key: 'variable', value: 'value' },
              { key: 'variable2', value: 'result2' },
              { key: 'variable3', value: 'result3' },
              { key: 'variable4', value: 'keyvalueresult3' }
            ]
          },
          "complex expansions": {
            variables: [
              { key: 'variable', value: 'value' },
              { key: 'variable2', value: 'result' },
              { key: 'variable3', value: 'key${variable}${variable2}' }
            ],
            keep_undefined: false,
            result: [
              { key: 'variable', value: 'value' },
              { key: 'variable2', value: 'result' },
              { key: 'variable3', value: 'keyvalueresult' }
            ]
          },
          "escaped characters in complex expansions keeping undefined are kept intact": {
            variables: [
              { key: 'variable3', value: 'key_${variable}_$${HOME}_%%HOME%%' },
              { key: 'variable', value: '$variable2' },
              { key: 'variable2', value: 'value' }
            ],
            keep_undefined: true,
            result: [
              { key: 'variable', value: 'value' },
              { key: 'variable2', value: 'value' },
              { key: 'variable3', value: 'key_value_$${HOME}_%%HOME%%' }
            ]
          },
          "escaped characters in complex expansions discarding undefined are kept intact": {
            variables: [
              { key: 'variable2', value: 'key_${variable4}_$${HOME}_%%HOME%%' },
              { key: 'variable', value: 'value_$${HOME}_%%HOME%%' }
            ],
            keep_undefined: false,
            result: [
              { key: 'variable', value: 'value_$${HOME}_%%HOME%%' },
              { key: 'variable2', value: 'key__$${HOME}_%%HOME%%' }
            ]
          },
          "out-of-order expansion": {
            variables: [
              { key: 'variable3', value: 'key$variable2$variable' },
              { key: 'variable', value: 'value' },
              { key: 'variable2', value: 'result' }
            ],
            keep_undefined: false,
            result: [
              { key: 'variable2', value: 'result' },
              { key: 'variable', value: 'value' },
              { key: 'variable3', value: 'keyresultvalue' }
            ]
          },
          "out-of-order complex expansion": {
            variables: [
              { key: 'variable', value: 'value' },
              { key: 'variable2', value: 'result' },
              { key: 'variable3', value: 'key${variable2}${variable}' }
            ],
            keep_undefined: false,
            result: [
              { key: 'variable', value: 'value' },
              { key: 'variable2', value: 'result' },
              { key: 'variable3', value: 'keyresultvalue' }
            ]
          },
          "missing variable discarding original": {
            variables: [
              { key: 'variable2', value: 'key$variable' }
            ],
            keep_undefined: false,
            result: [
              { key: 'variable2', value: 'key' }
            ]
          },
          "missing variable keeping original": {
            variables: [
              { key: 'variable2', value: 'key$variable' }
            ],
            keep_undefined: true,
            result: [
              { key: 'variable2', value: 'key$variable' }
            ]
          },
          "complex expansions with missing variable keeping original": {
            variables: [
              { key: 'variable4', value: 'key${variable}${variable2}${variable3}' },
              { key: 'variable', value: 'value' },
              { key: 'variable3', value: 'value3' }
            ],
            keep_undefined: true,
            result: [
              { key: 'variable', value: 'value' },
              { key: 'variable3', value: 'value3' },
              { key: 'variable4', value: 'keyvalue${variable2}value3' }
            ]
          },
          "complex expansions with raw variable with expand_raw_refs: true (default)": {
            variables: [
              { key: 'variable1', value: 'value1' },
              { key: 'raw_var', value: 'raw-$variable1', raw: true },
              { key: 'nonraw_var', value: 'nonraw-$variable1' },
              { key: 'variable2', value: '$raw_var and $nonraw_var' }
            ],
            keep_undefined: false,
            result: [
              { key: 'variable1', value: 'value1' },
              { key: 'raw_var', value: 'raw-$variable1', raw: true },
              { key: 'nonraw_var', value: 'nonraw-value1' },
              { key: 'variable2', value: 'raw-$variable1 and nonraw-value1' }
            ]
          },
          "complex expansions with raw variable with expand_raw_refs: false": {
            variables: [
              { key: 'variable1', value: 'value1' },
              { key: 'raw_var', value: 'raw-$variable1', raw: true },
              { key: 'nonraw_var', value: 'nonraw-$variable1' },
              { key: 'variable2', value: '$raw_var and $nonraw_var' }
            ],
            keep_undefined: false,
            expand_raw_refs: false,
            result: [
              { key: 'variable1', value: 'value1' },
              { key: 'raw_var', value: 'raw-$variable1', raw: true },
              { key: 'nonraw_var', value: 'nonraw-value1' },
              { key: 'variable2', value: '$raw_var and nonraw-value1' }
            ]
          },
          "variable value referencing password with special characters": {
            variables: [
              { key: 'VAR', value: '$PASSWORD' },
              { key: 'PASSWORD', value: 'my_password$$_%%_$A' },
              { key: 'A', value: 'value' }
            ],
            keep_undefined: false,
            result: [
              { key: 'VAR', value: 'my_password$$_%%_value' },
              { key: 'PASSWORD', value: 'my_password$$_%%_value' },
              { key: 'A', value: 'value' }
            ]
          },
          "cyclic dependency causes original array to be returned": {
            variables: [
              { key: 'variable', value: '$variable2' },
              { key: 'variable2', value: '$variable3' },
              { key: 'variable3', value: 'key$variable$variable2' }
            ],
            keep_undefined: false,
            result: [
              { key: 'variable', value: '$variable2' },
              { key: 'variable2', value: '$variable3' },
              { key: 'variable3', value: 'key$variable$variable2' }
            ]
          },
          "file variables with expand_file_refs: true": {
            variables: [
              { key: 'file_var', value: 'secret content', file: true },
              { key: 'variable1', value: 'var one' },
              { key: 'variable2', value: 'var two $variable1 $file_var' }
            ],
            result: [
              { key: 'file_var', value: 'secret content' },
              { key: 'variable1', value: 'var one' },
              { key: 'variable2', value: 'var two var one secret content' }
            ]
          },
          "file variables with expand_file_refs: false": {
            variables: [
              { key: 'file_var', value: 'secret content', file: true },
              { key: 'variable1', value: 'var one' },
              { key: 'variable2', value: 'var two $variable1 $file_var' }
            ],
            expand_file_refs: false,
            result: [
              { key: 'file_var', value: 'secret content' },
              { key: 'variable1', value: 'var one' },
              { key: 'variable2', value: 'var two var one $file_var' }
            ]
          }
        }
      end

      with_them do
        let(:collection) { Gitlab::Ci::Variables::Collection.new(variables) }
        let(:options) do
          { keep_undefined: keep_undefined,
            expand_raw_refs: expand_raw_refs,
            expand_file_refs: expand_file_refs }.compact
        end

        subject(:expanded_result) { collection.sort_and_expand_all(**options) }

        it 'returns Collection' do
          is_expected.to be_an_instance_of(Gitlab::Ci::Variables::Collection)
        end

        it 'expands variables' do
          var_hash = result.to_h { |env| [env.fetch(:key), env.fetch(:value)] }
            .with_indifferent_access
          expect(subject.to_hash).to eq(var_hash)
        end

        it 'preserves raw attribute' do
          expect(subject.pluck(:key, :raw).to_h).to eq(collection.pluck(:key, :raw).to_h)
        end
      end
    end

    context 'with the expanded size limit' do
      let(:collection) { described_class.new(variables) }
      let(:options) { {} }

      subject(:expanded_result) { collection.sort_and_expand_all(**options) }

      before do
        stub_const("#{described_class}::MAX_EXPANDED_SIZE", 10)
      end

      shared_examples 'exceeds the limit' do |key|
        it 'returns the original collection with an error', :aggregate_failures do
          expect(expanded_result.errors)
            .to eq("expanded variables exceed the limit of 10 B at variable `#{key}`")
          expect(expanded_result.to_hash).to eq(collection.to_hash)
        end
      end

      context 'when one value references a variable many times' do
        let(:variables) do
          [
            { key: 'big', value: 'abcde' },
            { key: 'many', value: '$big$big$big' }
          ]
        end

        it_behaves_like 'exceeds the limit', 'many'
      end

      context 'when nested references grow the value' do
        let(:variables) do
          [
            { key: 'a', value: '$b$b' },
            { key: 'b', value: '$c$c' },
            { key: 'c', value: 'abc' }
          ]
        end

        it_behaves_like 'exceeds the limit', 'a'
      end

      context 'when several values together exceed the limit' do
        let(:variables) do
          [
            { key: 'base', value: 'abcd' },
            { key: 'one', value: '$base' },
            { key: 'two', value: '$base' },
            { key: 'three', value: '$base' }
          ]
        end

        it 'returns an error' do
          expect(expanded_result.errors).to match(/expanded variables exceed the limit of 10 B at variable/)
        end
      end

      context 'when the expanded size is within the limit' do
        let(:variables) do
          [
            { key: 'a', value: 'abcde' },
            { key: 'b', value: '$a$a' }
          ]
        end

        it 'expands the variables', :aggregate_failures do
          expect(expanded_result.errors).to be_nil
          expect(expanded_result['b'].value).to eq('abcdeabcde')
        end
      end

      context 'when references are not expanded' do
        let(:variables) do
          [
            { key: 'file', value: 'abcdefghijk', file: true },
            { key: 'b', value: '$file$file' }
          ]
        end

        let(:options) { { expand_file_refs: false } }

        it 'does not count them as expanded' do
          expect(expanded_result.errors).to be_nil
        end
      end

      context 'when ci_variable_expansion_size_limit is disabled' do
        let(:variables) do
          [
            { key: 'big', value: 'abcde' },
            { key: 'many', value: '$big$big$big' }
          ]
        end

        before do
          stub_feature_flags(ci_variable_expansion_size_limit: false)
        end

        it 'expands the variables without logging', :aggregate_failures do
          expect(described_class).not_to receive(:log_expanded_size_limit_exceeded)

          expect(expanded_result.errors).to be_nil
          expect(expanded_result['many'].value).to eq('abcdeabcdeabcde')
        end
      end

      context 'when the limit is exceeded' do
        let(:variables) do
          [
            { key: 'big', value: 'abcde' },
            { key: 'many', value: '$big$big$big' }
          ]
        end

        it 'logs the expanded size and the variable key' do
          expect(Gitlab::AppJsonLogger).to receive(:info).with(
            message: 'CI variable expansion size limit exceeded',
            expanded_size_limit: 10,
            expanded_size: 15,
            variable_key: 'many'
          )

          expanded_result
        end
      end

      context 'when several variables are expanded' do
        let(:variables) do
          [
            { key: 'base', value: 'ab' },
            { key: 'one', value: '$base' },
            { key: 'two', value: '$base' },
            { key: 'three', value: '$base' }
          ]
        end

        it 'reads the flag once' do
          expect(described_class).to receive(:expanded_size_limit_enabled?).once.and_call_original

          expect(expanded_result.errors).to be_nil
        end
      end
    end
  end

  describe '.expanded_size_limit_enabled?', :request_store do
    it 'reads the flag once per request' do
      allow(Feature).to receive(:enabled?).and_call_original
      expect(Feature).to receive(:enabled?).with(:ci_variable_expansion_size_limit, :instance).once.and_call_original

      2.times { expect(described_class.expanded_size_limit_enabled?).to be(true) }
    end
  end

  describe '.check_expanded_size!' do
    before do
      stub_const("#{described_class}::MAX_EXPANDED_SIZE", 10)
    end

    it 'raises above the limit' do
      expect { described_class.check_expanded_size!(11) }.to raise_error(described_class::ExpandedSizeLimitError)
    end

    it 'does not raise at the limit' do
      expect { described_class.check_expanded_size!(10) }.not_to raise_error
    end

    context 'when ci_variable_expansion_size_limit is disabled' do
      before do
        stub_feature_flags(ci_variable_expansion_size_limit: false)
      end

      it 'does not raise above the limit' do
        expect { described_class.check_expanded_size!(11) }.not_to raise_error
      end
    end
  end

  describe '#to_s' do
    let(:variables) do
      [
        { key: 'VAR', value: 'value', public: true },
        { key: 'VAR2', value: 'value2', public: false }
      ]
    end

    let(:errors) { 'circular variable reference detected' }
    let(:collection) { described_class.new(variables, errors) }

    subject(:result) { collection.to_s }

    it { is_expected.to eq("[\"VAR\", \"VAR2\"], @errors='circular variable reference detected'") }
  end
end
