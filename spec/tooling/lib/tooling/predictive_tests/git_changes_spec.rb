# frozen_string_literal: true

require "gitlab_quality/test_tooling"
require "securerandom"

require_relative "../../../../../tooling/lib/tooling/predictive_tests/git_changes"

RSpec.describe Tooling::PredictiveTests::GitChanges, :silence_stdout, feature_category: :tooling do
  subject(:changes) do
    described_class.new(
      base_sha: 'base', clickhouse_client: clickhouse_client, project_path: 'gitlab-org/gitlab', git: git
    )
  end

  let(:clickhouse_client) do
    instance_double(GitlabQuality::TestTooling::ClickHouse::Client, query: rows)
  end

  let(:git) { instance_double(Proc) }
  let(:rows) { [{ 'sha' => 'capture' }] }

  describe '#since_last_capture' do
    context 'when the capture is newer than the MR base' do
      before do
        allow(git).to receive(:call).with('cat-file', any_args)
        allow(git).to receive(:call).with('show', '-s', '--format=%ct', 'capture').and_return("300\n")
        allow(git).to receive(:call).with('show', '-s', '--format=%ct', 'base').and_return("200\n")
      end

      it 'lists nothing' do
        expect(changes.since_last_capture).to eq([])
      end
    end

    context 'when the MR base is missing from the shallow clone' do
      before do
        allow(git).to receive(:call).with('cat-file', '-e', 'capture^{commit}')
        allow(git).to receive(:call).with('cat-file', '-e', 'base^{commit}').and_raise(RuntimeError, 'missing')
        allow(git).to receive(:call).with('fetch', '--depth=1', 'origin', 'base')
        allow(git).to receive(:call).with('show', '-s', '--format=%ct', 'capture').and_return("200\n")
        allow(git).to receive(:call).with('show', '-s', '--format=%ct', 'base').and_return("300\n")
        allow(git).to receive(:call).with('diff', '--name-only', '--diff-filter=ACMR', 'capture..base')
          .and_return("app/models/user.rb\n")
      end

      it 'fetches the base and lists the changed files', :aggregate_failures do
        expect(changes.since_last_capture).to eq(['app/models/user.rb'])
        expect(git).to have_received(:call).with('fetch', '--depth=1', 'origin', 'base')
      end
    end

    context 'when git fails' do
      before do
        allow(git).to receive(:call).and_raise(RuntimeError, 'boom')
      end

      it 'returns nil' do
        expect(changes.since_last_capture).to be_nil
      end
    end

    context 'when the map has no capture' do
      let(:rows) { [] }

      it 'returns nil' do
        expect(changes.since_last_capture).to be_nil
      end
    end
  end

  describe '#added_files' do
    context 'when git works' do
      before do
        allow(git).to receive(:call).with('cat-file', any_args)
        allow(git).to receive(:call).with('diff', '--name-only', '--no-renames', '--diff-filter=A', 'base', 'HEAD')
          .and_return("config/feature_flags/beta/a.yml\napp/models/b.rb\n")
      end

      it 'lists the files the MR adds' do
        expect(changes.added_files).to eq(%w[config/feature_flags/beta/a.yml app/models/b.rb])
      end
    end

    context 'when git fails' do
      before do
        allow(git).to receive(:call).and_raise(RuntimeError, 'boom')
      end

      it 'lists nothing' do
        expect(changes.added_files).to eq([])
      end
    end
  end

  describe '#files_naming' do
    context 'when git works' do
      before do
        allow(git).to receive(:call).with('grep', '-l', '-w', '-F', '-e', 'my_flag')
          .and_return("app/models/user.rb\nspec/models/user_spec.rb\n")
      end

      it 'lists the files that name the word' do
        expect(changes.files_naming('my_flag')).to eq(%w[app/models/user.rb spec/models/user_spec.rb])
      end
    end

    context 'when git fails' do
      before do
        allow(git).to receive(:call).and_raise(RuntimeError, 'boom')
      end

      it 'returns nil' do
        expect(changes.files_naming('my_flag')).to be_nil
      end
    end
  end

  describe 'running git grep for real' do
    subject(:changes) do
      described_class.new(base_sha: 'base', clickhouse_client: clickhouse_client, project_path: 'gitlab-org/gitlab')
    end

    it 'treats no match as an empty list' do
      expect(changes.files_naming("absent_word_#{SecureRandom.hex(8)}")).to eq([])
    end

    it 'lists the files that match' do
      expect(changes.files_naming('files_naming')).to include('tooling/lib/tooling/predictive_tests/git_changes.rb')
    end

    it 'returns nil when git fails' do
      status = instance_double(Process::Status, exitstatus: 128, success?: false)
      allow(Open3).to receive(:capture3).and_return(['', 'fatal: boom', status])

      expect(changes.files_naming('my_flag')).to be_nil
    end
  end
end
