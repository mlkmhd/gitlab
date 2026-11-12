# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::PipelineVariableItem, feature_category: :continuous_integration do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:pipeline) { create(:ci_pipeline) }
  let(:key) { 'TEST_VAR' }
  let(:value) { 'test_value' }
  let(:variable_type) { 'env_var' }
  let(:raw) { false }
  let(:attrs) { { key: key, value: value, variable_type: variable_type, raw: raw } }

  subject(:variable) { described_class.new(pipeline: pipeline, **attrs) }

  before do
    stub_feature_flags(ci_pipeline_variable_limits_override: false)
  end

  describe 'validations' do
    it { is_expected.to validate_inclusion_of(:variable_type).in_array(%w[env_var file]) }
    it { is_expected.to validate_inclusion_of(:raw).in_array([true, false]) }

    describe 'value length' do
      before do
        stub_const("#{described_class}::MAX_VALUE_LENGTH", 20)
      end

      it { is_expected.to validate_length_of(:value).is_at_most(20) }
    end

    describe 'value size' do
      let(:value) { 'a' * bytesize }
      let(:bytesize) { 11 }

      before do
        create(:plan_limits, plan: pipeline.project.actual_plan,
          ci_variable_value_size: 10, ci_variable_file_value_size: 20)
      end

      context 'with an env_var variable' do
        context 'when the value is at the limit' do
          let(:bytesize) { 10 }

          it { is_expected.to be_valid }
        end

        it 'is invalid over the limit and names the variable' do
          expect(variable).not_to be_valid
          expect(variable.errors.full_messages)
            .to contain_exactly("Value for variable TEST_VAR exceeds the 10 B limit. " \
              "For more information, see http://localhost/help/ci/variables/_index.md#pipeline-variable-limits")
        end
      end

      context 'with a file variable' do
        let(:variable_type) { 'file' }

        context 'when the value is at the limit' do
          let(:bytesize) { 20 }

          it { is_expected.to be_valid }
        end

        context 'when the value is over the limit' do
          let(:bytesize) { 21 }

          it 'is invalid and names the variable' do
            expect(variable).not_to be_valid
            expect(variable.errors.full_messages)
              .to contain_exactly("Value for variable TEST_VAR exceeds the 20 B limit. " \
                "For more information, see http://localhost/help/ci/variables/_index.md#pipeline-variable-limits")
          end
        end
      end

      context 'with a multibyte value' do
        let(:value) { 'é' * 6 }

        it 'counts bytes rather than characters' do
          expect(value.length).to be <= 10
          expect(variable).not_to be_valid
        end
      end

      context 'when the value is nil' do
        let(:value) { nil }

        it { is_expected.to be_valid }
      end

      context 'when the limit is 0, so it is not enforced' do
        before do
          pipeline.project.actual_limits.update!(ci_variable_value_size: 0)
        end

        it { is_expected.to be_valid }
      end

      context 'when the override flag is on for the top-level namespace' do
        before do
          stub_const("#{described_class}::OVERRIDE_FILE_VALUE_SIZE", 30)
          stub_feature_flags(ci_pipeline_variable_limits_override: pipeline.project.root_namespace)
        end

        it 'keeps the limit for env_var values' do
          expect(variable).not_to be_valid
        end

        context 'with a file variable' do
          let(:variable_type) { 'file' }

          context 'when the value is within the override' do
            let(:bytesize) { 30 }

            it { is_expected.to be_valid }
          end

          context 'when the value is over the override' do
            let(:bytesize) { 31 }

            it 'is invalid and names the override as the limit' do
              expect(variable).not_to be_valid
              expect(variable.errors.full_messages)
                .to contain_exactly("Value for variable TEST_VAR exceeds the 30 B limit. " \
                  "For more information, see http://localhost/help/ci/variables/_index.md#pipeline-variable-limits")
            end
          end

          context 'when the plan limit is higher than the override' do
            let(:bytesize) { 35 }

            before do
              pipeline.project.actual_limits.update!(ci_variable_file_value_size: 40)
            end

            it { is_expected.to be_valid }
          end
        end
      end

      context 'when the override flag is on for a different namespace' do
        let(:variable_type) { 'file' }
        let(:bytesize) { 21 }

        before do
          stub_feature_flags(ci_pipeline_variable_limits_override: create(:group))
        end

        it { is_expected.not_to be_valid }
      end

      context 'when the key is invalid' do
        let(:key) { 'invalid-key!' }

        it 'reports the key only, to keep the key out of the message' do
          expect(variable).not_to be_valid
          expect(variable.errors.full_messages)
            .to contain_exactly("Key can contain only letters, digits and '_'.")
        end
      end
    end

    context 'when the pipeline has no project' do
      let(:pipeline) { Ci::Pipeline.new }
      let(:value) { 'a' * 11 }

      before do
        create(:plan_limits, plan: create(:default_plan), ci_variable_value_size: 10)
      end

      it 'does not enforce a limit it cannot resolve' do
        expect(variable).to be_valid
      end
    end

    describe 'value size with the column defaults' do
      let(:value) { 'a' * 1.megabyte }

      it 'enforces nothing, because no limit is set by default' do
        expect(variable).to be_valid
      end
    end

    describe 'key' do
      it { is_expected.to validate_presence_of(:key) }
      it { is_expected.to validate_length_of(:key).is_at_most(described_class::MAX_KEY_LENGTH) }

      where(:key, :valid) do
        'var'      | true
        'test_var' | true
        'VAR_123'  | true
        'VAR 123'  | false
        'var-123'  | false
        'VAR@NAME' | false
        ''         | false
      end

      with_them do
        it 'validates key format' do
          expect(variable.valid?).to be(valid)
          expect(variable.errors[:key]).to include("can contain only letters, digits and '_'.") unless valid
        end
      end
    end
  end

  describe 'defaults' do
    let(:attrs) { {} }

    it { expect(variable.variable_type).to eq('env_var') }
    it { expect(variable.raw).to be(false) }
  end

  describe '#raw?' do
    where(:raw) { [true, false] }

    with_them do
      it 'is equivalent to raw' do
        expect(variable.raw?).to eq(variable.raw)
      end
    end
  end

  describe '#key=' do
    where(:key) { [' MY_VAR', 'MY_VAR  ', ' MY_VAR '] }

    with_them do
      it 'strips whitespace from the input' do
        expect(variable.key).to eq('MY_VAR')
      end
    end
  end

  describe '#variable_type=' do
    where(:variable_type, :expected_variable_type, :valid) do
      'env_var' | 'env_var'  | true
      'file'    | 'file'     | true
      'invalid' | 'invalid'  | false
      :env_var  | 'env_var'  | true
      :file     | 'file'     | true
      :invalid  | 'invalid'  | false
      1         | 'env_var'  | true
      2         | 'file'     | true
      3         | nil        | false
      nil       | nil        | false
    end

    with_them do
      it 'handles string, symbol, integer, and nil values as expected' do
        expect(variable.variable_type).to eq(expected_variable_type)
        expect(variable.valid?).to be(valid)
      end
    end
  end

  describe '#id' do
    let(:expected_id) { Digest::SHA256.hexdigest("#{pipeline.id}/#{key}") }

    it 'generates a SHA256 hash based on pipeline id and key' do
      expect(variable.id).to eq(expected_id)
    end

    it 'supports a global ID' do
      expect(variable.to_global_id.to_s).to eq("gid://gitlab/#{described_class.name}/#{expected_id}")
    end
  end

  describe '#to_hash_variable' do
    it 'returns the expected hash' do
      expect(variable.to_hash_variable).to eq({ key: key, value: value, public: false, file: false, raw: false })
    end
  end

  describe '#file?' do
    context 'when variable_type is not file' do
      it { expect(variable.file?).to be(false) }
    end

    context 'when variable_type is file' do
      let(:variable_type) { 'file' }

      it { expect(variable.file?).to be(true) }
    end
  end

  describe '#hook_attrs' do
    it 'returns a hash with key and value only' do
      expect(variable.hook_attrs).to eq({ key: key, value: value })
    end
  end
end
