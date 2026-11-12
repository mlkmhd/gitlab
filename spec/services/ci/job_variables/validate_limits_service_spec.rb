# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::JobVariables::ValidateLimitsService, feature_category: :continuous_integration do
  let_it_be(:project) { create(:project) }

  let(:variables) { [{ key: 'TEST_VAR', value: 'value' }] }

  subject(:result) { described_class.new(project, variables).execute }

  it { is_expected.to be_success }

  describe 'the shapes nested attributes accept' do
    before do
      project.actual_limits.update!(ci_job_variables_count: 1)
    end

    shared_examples 'counts two variables' do
      it { is_expected.to be_error }
    end

    context 'with an array of hashes' do
      let(:variables) { [{ key: 'A', value: 'x' }, { key: 'B', value: 'y' }] }

      it_behaves_like 'counts two variables'
    end

    context 'with a hash keyed by index' do
      let(:variables) { { '0' => { key: 'A', value: 'x' }, '1' => { key: 'B', value: 'y' } } }

      it_behaves_like 'counts two variables'
    end

    context 'with a hash whose keys are not all numeric' do
      let(:variables) { { 'key' => { key: 'A', value: 'x' }, '1' => { key: 'B', value: 'y' } } }

      it_behaves_like 'counts two variables'
    end

    context 'with an empty hash' do
      let(:variables) { {} }

      it { is_expected.to be_success }
    end
  end

  context 'when there are no variables' do
    let(:variables) { nil }

    it { is_expected.to be_success }
  end

  describe 'count limit' do
    before do
      project.actual_limits.update!(ci_job_variables_count: 2)
    end

    context 'when the count is at the limit' do
      let(:variables) { Array.new(2) { |i| { key: "VAR_#{i}", value: 'x' } } }

      it { is_expected.to be_success }
    end

    context 'when the count is over the limit' do
      let(:variables) { Array.new(3) { |i| { key: "VAR_#{i}", value: 'x' } } }

      it 'returns an error naming the limit' do
        expect(result).to be_error
        expect(result.message).to eq('The number of job variables exceeds the limit of 2. ' \
          'For more information, see http://localhost/help/ci/jobs/job_control.md#job-variable-limits')
      end

      context 'when the limit is 0, so it is not enforced' do
        before do
          project.actual_limits.update!(ci_job_variables_count: 0)
        end

        it { is_expected.to be_success }
      end
    end
  end

  describe 'size limit' do
    let(:variables) { [{ key: 'TEST_VAR', value: 'a' * bytesize }] }
    let(:bytesize) { 11 }

    before do
      project.actual_limits.update!(ci_variable_value_size: 10, ci_variable_file_value_size: 20)
    end

    context 'when the value is at the limit' do
      let(:bytesize) { 10 }

      it { is_expected.to be_success }
    end

    it 'returns an error naming the variable' do
      expect(result).to be_error
      expect(result.message).to eq('Value for variable TEST_VAR exceeds the 10 B limit. ' \
        'For more information, see http://localhost/help/ci/jobs/job_control.md#job-variable-limits')
    end

    context 'when the limit is 0, so it is not enforced' do
      before do
        project.actual_limits.update!(ci_variable_value_size: 0)
      end

      it { is_expected.to be_success }
    end

    context 'with a file variable' do
      let(:variables) { [{ key: 'TEST_VAR', value: 'a' * bytesize, variable_type: 'file' }] }

      context 'when the value is at the limit' do
        let(:bytesize) { 20 }

        it { is_expected.to be_success }
      end

      context 'when the value is over the limit' do
        let(:bytesize) { 21 }

        it 'returns an error naming the file limit' do
          expect(result).to be_error
          expect(result.message).to eq('Value for variable TEST_VAR exceeds the 20 B limit. ' \
            'For more information, see http://localhost/help/ci/jobs/job_control.md#job-variable-limits')
        end

        context 'when the file limit is 0, so it is not enforced' do
          before do
            project.actual_limits.update!(ci_variable_file_value_size: 0)
          end

          it { is_expected.to be_success }
        end
      end
    end

    context 'with a multibyte value' do
      let(:variables) { [{ key: 'TEST_VAR', value: 'é' * 6 }] }

      it 'counts bytes rather than characters' do
        expect(variables.first[:value].length).to be <= 10
        expect(result).to be_error
      end
    end

    context 'when the value is nil' do
      let(:variables) { [{ key: 'TEST_VAR', value: nil }] }

      it { is_expected.to be_success }
    end

    context 'when only a later variable is over the limit' do
      let(:variables) do
        [{ key: 'FIRST', value: 'a' }, { key: 'SECOND', value: 'a' * 11 }]
      end

      it 'names the offending variable' do
        expect(result).to be_error
        expect(result.message).to eq('Value for variable SECOND exceeds the 10 B limit. ' \
          'For more information, see http://localhost/help/ci/jobs/job_control.md#job-variable-limits')
      end
    end

    context 'when the key is longer than a key may be' do
      let(:variables) { [{ key: 'K' * 300, value: 'a' * 11 }] }

      it 'truncates the key in the message' do
        expect(result).to be_error
        expect(result.message).not_to include('K' * 300)
        expect(result.message).to include(('K' * 300).truncate(Ci::HasVariable::MAX_KEY_LENGTH))
      end
    end
  end

  describe 'when the limits are not set' do
    let(:variables) { [{ key: 'TEST_VAR', value: 'a' * 2.megabytes }] }

    it { is_expected.to be_success }

    context 'with far more variables than any plan would allow' do
      let(:variables) { Array.new(5000) { |i| { key: "VAR_#{i}", value: 'x' } } }

      it { is_expected.to be_success }
    end
  end

  describe 'the GitLab.com values' do
    before do
      project.actual_limits.update!(
        ci_job_variables_count: 200,
        ci_variable_value_size: 128.kilobytes,
        ci_variable_file_value_size: 1.megabyte
      )
    end

    let(:variables) { [{ key: 'TEST_VAR', value: 'a' * (128.kilobytes + 1) }] }

    it 'reports the value size limit as it is written in the docs' do
      expect(result).to be_error
      expect(result.message).to eq('Value for variable TEST_VAR exceeds the 128 KiB limit. ' \
        'For more information, see http://localhost/help/ci/jobs/job_control.md#job-variable-limits')
    end

    context 'with a file variable' do
      let(:variables) { [{ key: 'TEST_VAR', value: 'a' * (1.megabyte + 1), variable_type: 'file' }] }

      it 'reports the file size limit as it is written in the docs' do
        expect(result).to be_error
        expect(result.message).to eq('Value for variable TEST_VAR exceeds the 1 MiB limit. ' \
          'For more information, see http://localhost/help/ci/jobs/job_control.md#job-variable-limits')
      end
    end

    context 'with more variables than a job may have' do
      let(:variables) { Array.new(201) { |i| { key: "VAR_#{i}", value: 'x' } } }

      it 'reports the count limit as it is written in the docs' do
        expect(result).to be_error
        expect(result.message).to eq('The number of job variables exceeds the limit of 200. ' \
          'For more information, see http://localhost/help/ci/jobs/job_control.md#job-variable-limits')
      end
    end
  end

  describe 'disabling a limit' do
    before do
      project.actual_limits.update!(ci_job_variables_count: 1)
    end

    let(:variables) { Array.new(2) { |i| { key: "VAR_#{i}", value: 'x' } } }

    it { is_expected.to be_error }

    context 'when the limit is set back to 0' do
      before do
        project.actual_limits.update!(ci_job_variables_count: 0)
      end

      it { is_expected.to be_success }
    end
  end
end
