# frozen_string_literal: true

require 'open3'
require_relative '../../caproni/scripts/seed'

RSpec.describe Seed do
  # CI runs it by absolute path, which is when a seeder loading seed.rb could run it twice
  it 'loads the seeders when run as a script by absolute path' do
    script = File.expand_path('../../caproni/scripts/seed.rb', __dir__)
    _, err, status = Open3.capture3(RbConfig.ruby, script)

    expect(status.exitstatus).to eq(1)
    expect(err).to start_with("Usage: #{script} admin_token|oidc_application|gitlab_duo")
  end

  describe '.program' do
    let(:first) { Module.new { def self.program_from_env = "first\n" } }
    let(:second) { Module.new { def self.program_from_env = "second\n" } }

    it 'runs the programs of every seeder in order, in one runner program' do
      expect(described_class.program([first, second])).to eq("first\nsecond\n")
    end
  end

  describe '.wait_for_database_program' do
    # The runner can boot before the migrations job has seeded root
    it 'waits for the root user, and gives up after the wait timeout' do
      program = described_class.wait_for_database_program

      expect(program).to include("User.exists?(username: 'root')")
      expect(program).to include("+ #{described_class::WAIT_TIMEOUT}")
      expect { RubyVM::InstructionSequence.compile(program) }.not_to raise_error
    end
  end

  describe '.toolbox_pod' do
    let(:ok) { instance_double(Process::Status, success?: true) }
    let(:failed) { instance_double(Process::Status, success?: false) }

    before do
      allow(described_class).to receive(:sleep)
      allow(described_class).to receive(:puts)
    end

    it 'waits until a toolbox pod exists and is ready' do
      allow(described_class).to receive(:caproni).with('config', 'gitlab', 'get', any_args)
        .and_return(['', 'error: no cluster', failed], ['gitlab-toolbox-abc', '', ok])
      allow(described_class).to receive(:caproni).with('config', 'gitlab', 'wait', any_args)
        .and_return(['', '', ok])

      expect(described_class.toolbox_pod('config', 'gitlab', described_class.monotonic_now + 60))
        .to eq('gitlab-toolbox-abc')
    end

    # A deploy retry can replace the pod while it's being waited on
    it 'keeps waiting when the pod exists but is not ready yet' do
      allow(described_class).to receive(:caproni).with('config', 'gitlab', 'get', any_args)
        .and_return(['gitlab-toolbox-old', '', ok], ['gitlab-toolbox-new', '', ok])
      allow(described_class).to receive(:caproni).with('config', 'gitlab', 'wait', any_args)
        .and_return(['', 'error: pods "gitlab-toolbox-old" not found', failed], ['', '', ok])

      expect(described_class.toolbox_pod('config', 'gitlab', described_class.monotonic_now + 60))
        .to eq('gitlab-toolbox-new')
    end

    it 'reports the wait error when the pod never becomes ready' do
      allow(described_class).to receive(:caproni).with('config', 'gitlab', 'get', any_args)
        .and_return(['gitlab-toolbox-abc', '', ok])
      allow(described_class).to receive(:caproni).with('config', 'gitlab', 'wait', any_args)
        .and_return(['', 'error: timed out waiting for the condition on pods/gitlab-toolbox-abc', failed])

      expect { described_class.toolbox_pod('config', 'gitlab', described_class.monotonic_now - 1) }
        .to raise_error(SystemExit)
        .and output(/timed out waiting for the condition/).to_stderr
    end

    it 'gives up at the deadline it is given, with the last kubectl error' do
      allow(described_class).to receive(:caproni).and_return(['', 'error: no cluster', failed])

      expect { described_class.toolbox_pod('config', 'gitlab', described_class.monotonic_now - 1) }
        .to raise_error(SystemExit)
        .and output(/wasn't ready within \d+s: error: no cluster/).to_stderr
    end
  end
end
