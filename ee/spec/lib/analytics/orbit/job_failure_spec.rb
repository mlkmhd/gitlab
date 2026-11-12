# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::JobFailure, feature_category: :knowledge_graph do
  let_it_be(:project) { create(:project, :private) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project) }

  subject(:failure) { described_class.new(job, user).execute }

  context 'with a JUnit report' do
    let_it_be(:job) { create(:ci_build, :failed, :test_reports, pipeline: pipeline, project: project) }

    it 'lists the failed tests with their failure output' do
      expect(failure[:failed_tests]).to include(
        name: 'Test#sum when a is 1 and b is 2 returns summary', classname: 'spec.test_spec',
        file: './spec/test_spec.rb', output: a_string_including('expected: 3')
      )
    end

    it 'marks the failed tests as truncated when they are capped' do
      stub_const("#{described_class}::MAX_TESTS", 1)

      expect(failure).to include(failed_tests: [anything], truncated: [:failed_tests])
    end

    it 'leaves the failed tests out when the access token cannot read the report' do
      expect(described_class.new(job, user, read_tests: false).execute).not_to have_key(:failed_tests)
    end
  end

  context 'with a job log' do
    let_it_be(:job) { create(:ci_build, :failed, pipeline: pipeline, project: project) }

    let(:log) do
      [
        "section_start:1:prepare_executor\r\e[0KPreparing the executor",
        "Pulling image ruby:3.3",
        "section_end:1:prepare_executor\r\e[0K",
        "section_start:2:step_script\r\e[0KExecuting \"step_script\" stage of the job script",
        "$ bundle exec rspec",
        "\e[31mexpected 1, got 2\e[0m",
        "section_end:2:step_script\r\e[0K",
        "section_start:3:upload_artifacts_on_failure\r\e[0KUploading artifacts for failed job",
        "section_end:3:upload_artifacts_on_failure\r\e[0K"
      ].join("\n")
    end

    before do
      allow(job).to receive_messages(has_trace?: true, trace: instance_double(Gitlab::Ci::Trace, raw: log))
    end

    it 'keeps only the script output, without terminal codes' do
      expect(failure).to eq(log: "$ bundle exec rspec\nexpected 1, got 2")
    end

    context 'with other log shapes' do
      using RSpec::Parameterized::TableSyntax

      # Each part is a section name, or - for no section, followed by its lines.
      where(:parts, :cut, :expected) do
        [%w[- FAILURE], %w[after_script cleanup], %w[upload_artifacts_on_failure up]] | true | "...\nFAILURE\ncleanup"
        [%w[- Running], %w[step_script run], %w[rspec_run failures], %w[- ERROR]] | false | "run\nfailures"
        [%w[- Running], %w[prepare_executor pull], %w[- ERROR]] | false | "Running\npull\nERROR"
      end

      with_them do
        let(:log) do
          parts.flat_map do |name, *lines|
            name == '-' ? lines : ["section_start:1:#{name}\r\e[0K#{name}", *lines, "section_end:1:#{name}\r\e[0K"]
          end.join("\n")
        end

        it 'keeps the script output' do
          stub_const("#{described_class}::SCAN_LINES", 1) if cut

          expect(failure).to eq(log: expected)
        end
      end
    end

    context 'with several script commands' do
      let(:log) do
        [
          "section_start:1:step_script\r\e[0Kstep_script", '$ bundle install', 'Fetching rake 13.2.1',
          '$ bundle exec rspec', *(1..6).map { |n| "Downloading #{n}%" },
          'Failure/Error: expect(x).to eq(1)', "section_end:1:step_script\r\e[0K",
          "section_start:2:after_script\r\e[0Kafter_script", '$ ./cleanup.sh', 'cleaned',
          "section_end:2:after_script\r\e[0K"
        ].join("\n")
      end

      it 'keeps the whole script output when it fits' do
        expect(failure).to eq(
          log: "$ bundle install\nFetching rake 13.2.1\n$ bundle exec rspec\n" \
            "#{(1..6).map { |n| "Downloading #{n}%" }.join("\n")}\n" \
            "Failure/Error: expect(x).to eq(1)\n$ ./cleanup.sh\ncleaned"
        )
      end

      it 'folds runs of similar lines only when the output does not fit' do
        stub_const("#{described_class}::LOG_BYTES", 150)

        expect(failure).to eq(
          log: "...\nFetching rake 13.2.1\n$ bundle exec rspec\nDownloading 1%\n... (4 similar lines)\n" \
            "Downloading 6%\nFailure/Error: expect(x).to eq(1)\n$ ./cleanup.sh\ncleaned"
        )
      end

      it 'keeps the end of the script and after_script output within the byte budget' do
        stub_const("#{described_class}::LOG_BYTES", 60)

        expect(failure).to eq(log: "...\nDownloading 6%\nFailure/Error: expect(x).to eq(1)\n...\ncleaned")
      end

      it 'clips long lines' do
        stub_const("#{described_class}::LINE_CHARS", 8)

        expect(failure[:log]).to include("Failure/...\n")
      end

      it 'marks a requested job log as truncated when folding alone made it fit' do
        stub_const("#{described_class}::FULL_LOG_BYTES", 180)

        expect(described_class.new(job, user, full_log: true).execute).to eq(
          log: "$ bundle install\nFetching rake 13.2.1\n$ bundle exec rspec\nDownloading 1%\n... (4 similar lines)\n" \
            "Downloading 6%\nFailure/Error: expect(x).to eq(1)\n$ ./cleanup.sh\ncleaned",
          truncated: [:log]
        )
      end

      it 'marks a requested job log as truncated when lines were left out' do
        stub_const("#{described_class}::FULL_LOG_BYTES", 30)

        expect(described_class.new(job, user, full_log: true).execute).to include(truncated: [:log])
      end
    end

    context 'with long after_script output' do
      let(:log) do
        [
          "section_start:1:step_script\r\e[0Kstep_script", '$ make test', 'FAIL: test_x',
          "section_end:1:step_script\r\e[0K", "section_start:2:after_script\r\e[0Kafter_script",
          *('a'..'z').map { |name| "removing #{name}.tmp" }, "section_end:2:after_script\r\e[0K"
        ].join("\n")
      end

      it 'keeps the job script failure ahead of the after_script output' do
        stub_const("#{described_class}::LOG_BYTES", 120)

        expect(failure).to eq(log: "$ make test\nFAIL: test_x\n...\nremoving y.tmp\nremoving z.tmp")
      end
    end

    it 'does not mark a requested job log that fits as truncated' do
      expect(described_class.new(job, user, full_log: true).execute)
        .to eq(log: "$ bundle exec rspec\nexpected 1, got 2")
    end

    it 'leaves the log out when the user cannot read it' do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(user, :read_build_trace, job).and_return(false)

      expect(failure).to eq({})
    end

    it 'leaves the log out when the access token cannot read it' do
      expect(described_class.new(job, user, read_log: false).execute).to eq({})
    end
  end
end
