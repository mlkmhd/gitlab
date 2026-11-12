# frozen_string_literal: true

require 'fast_spec_helper'
require_relative '../../../scripts/ci/otel_span_disk_usage'

RSpec.describe OtelSpanDiskUsage, feature_category: :tooling do
  let(:collector) { described_class.new(project_dir: Dir.pwd) }

  describe '#snapshot' do
    before do
      stub_const('RUBY_PLATFORM', 'x86_64-linux')
      allow(collector).to receive(:filesystem_stat).and_return(
        ['4096 1000 400 12 abcd', instance_double(Process::Status, success?: true)])
    end

    it 'uses blocks available to unprivileged processes and filesystem block size' do
      expect(collector.snapshot).to include('space_total_bytes' => 4_096_000,
        'space_available_bytes' => 1_638_400, 'inodes_available' => 12)
    end

    it 'omits unsupported platforms' do
      stub_const('RUBY_PLATFORM', 'arm64-darwin')

      expect(collector.snapshot).to be_empty
    end

    it 'omits unavailable paths' do
      expect(described_class.new(project_dir: '/missing/otel-project').snapshot).to be_empty
    end

    it 'omits its own stat timeout without changing the command outcome' do
      allow(collector).to receive(:filesystem_stat).and_raise(described_class::StatTimeout)

      expect(collector.snapshot).to be_empty
    end

    it 'does not swallow an enclosing timeout' do
      allow(collector).to receive(:filesystem_stat).and_raise(Timeout::Error)

      expect { collector.snapshot }.to raise_error(Timeout::Error)
    end

    context 'when stat exits unsuccessfully' do
      before do
        allow(collector).to receive(:filesystem_stat).and_return(
          ['', instance_double(Process::Status, success?: false)])
      end

      it 'omits measurements' do
        expect(collector.snapshot).to be_empty
      end
    end

    where(:output) { ['invalid', '4096 1000 1001 12 abcd', '0 1000 400 12 abcd', '4096 1000 -1 12 abcd'] }

    with_them do
      it 'rejects malformed or inconsistent measurements' do
        allow(collector).to receive(:filesystem_stat).and_return(
          [output, instance_double(Process::Status, success?: true)])

        expect(collector.snapshot).to be_empty
      end
    end
  end

  describe '#attributes' do
    let(:snapshot) do
      { 'identity' => [1, 'abcd'], 'space_available_bytes' => 100,
        'space_total_bytes' => 1000, 'inodes_available' => 12 }
    end

    it 'emits independent endpoint snapshots rather than exclusive command consumption' do
      expect(collector.attributes(snapshot, snapshot.merge('space_available_bytes' => 200))).to include(
        'gitlab.cicd.disk.scope' => 'project_filesystem',
        'gitlab.cicd.disk.space_available_start_bytes' => 100,
        'gitlab.cicd.disk.space_available_end_bytes' => 200,
        'gitlab.cicd.disk.inodes_available_end' => 12
      )
    end

    it 'omits changed filesystems' do
      expect(collector.attributes(snapshot, snapshot.merge('identity' => [2, 'other']))).to be_empty
    end

    it 'omits missing snapshots' do
      expect(collector.attributes(nil, snapshot)).to be_empty
    end

    context 'with invalid measurements' do
      where(:value) { [nil, -1, '100', 1 << 63, (1 << 64) - 1] }

      with_them do
        let(:snapshot) { { 'identity' => [1, 'abcd'], 'space_available_bytes' => value } }

        it 'omits measurements and the scope when no valid values remain' do
          expect(collector.attributes(snapshot, snapshot)).to be_empty
        end
      end
    end

    it 'omits unsigned inode sentinels while retaining valid byte measurements' do
      current = snapshot.merge('inodes_available' => (1 << 64) - 1)

      expect(collector.attributes(current, current)).to include(
        'gitlab.cicd.disk.space_available_end_bytes' => 100)
      expect(collector.attributes(current, current)).not_to have_key('gitlab.cicd.disk.inodes_available_end')
    end
  end

  describe '#snapshot with a stat subprocess' do
    let(:stdin) { instance_double(IO, close: nil) }
    let(:stdout) { instance_double(IO) }
    let(:stderr) { instance_double(IO, read: '') }
    let(:status) { instance_double(Process::Status, success?: true) }
    let(:waiter) { instance_double(Process::Waiter, value: status, alive?: false) }

    before do
      stub_const('RUBY_PLATFORM', 'x86_64-linux')
      allow(stdout).to receive(:read).with(1024).and_return('4096 1000 400 12 abcd')
      allow(Open3).to receive(:popen3).with(
        { 'LC_ALL' => 'C' }, 'stat', '-f', '-c', '%S %b %a %d %i', '--', Dir.pwd
      ).and_yield(stdin, stdout, stderr, waiter)
    end

    it 'reads bounded output and returns filesystem measurements' do
      expect(collector.snapshot).to include('space_available_bytes' => 1_638_400)
    end

    context 'when the subprocess times out while still running' do
      before do
        allow(stdout).to receive(:read).with(1024).and_raise(described_class::StatTimeout)
        allow(waiter).to receive_messages(alive?: true, pid: 12345)
      end

      it 'kills the subprocess and omits measurements' do
        expect(Process).to receive(:kill).with('KILL', 12345)

        expect(collector.snapshot).to be_empty
      end
    end

    context 'when stat succeeds without any output' do
      before do
        allow(stdout).to receive(:read).with(1024).and_return(nil)
      end

      it 'omits measurements' do
        expect(collector.snapshot).to be_empty
      end
    end

    context 'when stat exceeds its own deadline' do
      before do
        stub_const('OtelSpanDiskUsage::STAT_TIMEOUT_S', 0.01)
        allow(stdout).to receive(:read).with(1024) { sleep 5 }
        allow(waiter).to receive_messages(alive?: true, pid: 12345)
      end

      it 'kills the subprocess and omits measurements' do
        expect(Process).to receive(:kill).with('KILL', 12345)

        expect(collector.snapshot).to be_empty
      end
    end

    context 'when an enclosing timeout fires while stat is still running' do
      before do
        allow(stdout).to receive(:read).with(1024) { sleep 5 }
        allow(waiter).to receive_messages(alive?: true, pid: 12345)
      end

      it 'kills the subprocess and lets the enclosing boundary decide' do
        expect(Process).to receive(:kill).with('KILL', 12345)

        expect { Timeout.timeout(0.05) { collector.snapshot } }.to raise_error(Timeout::Error)
      end
    end

    context 'when stat cannot be started' do
      before do
        allow(Open3).to receive(:popen3).and_raise(Errno::ENOENT)
      end

      it 'omits measurements' do
        expect(collector.snapshot).to be_empty
      end
    end

    context 'when an outer timeout interrupts subprocess setup' do
      before do
        allow(waiter).to receive_messages(alive?: true, pid: 12345)
        allow(Open3).to receive(:popen3) do |*_, &block|
          interrupted = Thread.current
          Thread.new { interrupted.raise(Timeout::Error) }.join
          block.call(stdin, stdout, stderr, waiter)
        end
      end

      it 'establishes cleanup before delivering the timeout to the enclosing boundary' do
        expect(Process).to receive(:kill).with('KILL', 12345)

        expect { collector.snapshot }.to raise_error(Timeout::Error)
      end
    end

    context 'when an outer timeout interrupts stdin close' do
      before do
        allow(waiter).to receive_messages(alive?: true, pid: 12345)
        allow(stdin).to receive(:close).and_raise(Timeout::Error)
      end

      it 'kills the subprocess before Open3 waits for it and propagates the timeout' do
        expect(Process).to receive(:kill).with('KILL', 12345)

        expect { collector.snapshot }.to raise_error(Timeout::Error)
      end
    end
  end
end
