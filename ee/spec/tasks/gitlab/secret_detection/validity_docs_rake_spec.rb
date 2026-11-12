# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'gitlab:secret_detection:validity_docs tasks', :silence_stdout, feature_category: :secret_detection do
  let(:doc_path) { Pathname.new(Dir.mktmpdir).join('detected_secrets.md') }
  let(:klass) { Security::SecretDetection::ValidityCheckDocs }
  let(:content) { "stale\n" }
  let(:new_content) { "fresh\n" }
  let(:unlisted) { [] }

  before do
    Rake.application.rake_require 'tasks/gitlab/secret_detection/validity_docs'

    stub_const("#{klass}::DOC_PATH", doc_path)
    File.write(doc_path, content)
    allow(klass).to receive(:generate).and_return([new_content, unlisted])
  end

  after do
    FileUtils.rm_rf(doc_path.dirname)
  end

  describe 'validity_docs:compile' do
    subject(:run_task) { run_rake_task('gitlab:secret_detection:validity_docs:compile') }

    it 'writes the generated content' do
      run_task

      expect(File.read(doc_path)).to eq(new_content)
    end

    context 'when a rule has no table row' do
      let(:unlisted) { %w[NewRule] }

      it 'warns' do
        expect { run_task }.to output(/No table row for: NewRule/).to_stderr
      end
    end
  end

  describe 'validity_docs:check' do
    subject(:run_task) { run_rake_task('gitlab:secret_detection:validity_docs:check') }

    context 'when the docs are up to date' do
      let(:content) { new_content }

      it 'does not abort' do
        expect { run_task }.not_to raise_error
      end

      context 'when a rule has no table row' do
        let(:unlisted) { %w[NewRule] }

        it 'warns' do
          expect { run_task }.to output(/No table row yet for: NewRule/).to_stderr
        end
      end
    end

    context 'when the docs are out of date' do
      it 'aborts' do
        expect { run_task }
          .to raise_error(SystemExit)
          .and output(/Validity check columns are out of date/).to_stderr
      end
    end
  end
end
