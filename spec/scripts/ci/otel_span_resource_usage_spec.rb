# frozen_string_literal: true

require 'fast_spec_helper'
require 'tmpdir'
require_relative '../../../scripts/ci/otel_span_resource_usage'

RSpec.describe OtelSpanResourceUsage, feature_category: :tooling do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:mountpoint) { File.join(tmp_dir, 'cgroup') }
  let(:directory) { File.join(mountpoint, 'job') }
  let(:cgroup_file) { File.join(tmp_dir, 'membership') }
  let(:mountinfo_file) { File.join(tmp_dir, 'mountinfo') }
  let(:prefix) { described_class::PREFIX }
  let(:disk) { instance_double(OtelSpanDiskUsage, snapshot: {}, attributes: {}) }
  let(:network) { instance_double(OtelSpanNetworkUsage, snapshot: {}, attributes: {}) }
  let(:network_enabled) { true }
  let(:collector) do
    described_class.new(cgroup_file: cgroup_file, mountinfo_file: mountinfo_file, disk: disk, network: network,
      network_enabled: network_enabled)
  end

  before do
    FileUtils.mkdir_p(directory)
    File.write(cgroup_file, "0::/job\n")
    File.write(mountinfo_file, "1 2 0:1 / #{mountpoint} rw - cgroup2 cgroup rw\n")
    write_counters(directory, cpu: 100, memory: 200, limit: 1000)
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  def write_counters(path, cpu: 100, memory: 200, limit: 1000, events: 0)
    File.write(File.join(path, 'cpu.stat'), "usage_usec #{cpu}\nuser_usec 50\n")
    File.write(File.join(path, 'memory.current'), memory.to_s)
    File.write(File.join(path, 'memory.max'), limit.to_s)
    File.write(File.join(path, 'memory.events'), "high #{events}\nmax #{events}\noom #{events}\noom_kill #{events}\n")
  end

  describe '#attributes' do
    context 'when network collection is disabled' do
      let(:network_enabled) { false }

      it 'retains cgroup observations without sampling or attributing network traffic', :aggregate_failures do
        previous = Gitlab::Json.generate(collector.snapshot)
        expect(collector.attributes(previous)).to include("#{prefix}scope" => 'current_cgroup')
        expect(network).not_to have_received(:snapshot)
        expect(network).not_to have_received(:attributes)
      end
    end

    context 'when the caller does not enable network collection' do
      before do
        stub_env('GLCI_OTEL_NETWORK_USAGE', 'true')
      end

      it 'defaults network sampling to off regardless of the environment', :aggregate_failures do
        default_collector = described_class.new(cgroup_file: cgroup_file, mountinfo_file: mountinfo_file,
          disk: disk, network: network)
        expect(default_collector.snapshot).not_to have_key('network')
        expect(network).not_to have_received(:snapshot)
      end
    end

    context 'when only network measurements are available' do
      before do
        File.unlink(cgroup_file)
        allow(network).to receive_messages(snapshot: { 'identity' => [[1, 2], [['eth0', 2, false]]] },
          attributes: { 'gitlab.cicd.network.receive_bytes' => 100 })
      end

      it 'retains network enrichment independently of disk and cgroup data' do
        expect(collector.attributes(Gitlab::Json.generate(collector.snapshot))).to eq(
          'gitlab.cicd.network.receive_bytes' => 100)
      end
    end

    context 'with the real network collector' do
      let(:counters_file) { File.join(tmp_dir, 'net_dev') }
      let(:namespace_file) { File.join(tmp_dir, 'net_ns') }
      let(:network) { OtelSpanNetworkUsage.new(counters_file: counters_file, namespace_file: namespace_file) }
      let(:ethernet) { instance_double(Socket::Ifaddr, name: 'eth0', ifindex: 2, flags: 0x11043) }

      before do
        stub_const('RUBY_PLATFORM', 'x86_64-linux')
        File.write(namespace_file, '')
        allow(Socket).to receive(:getifaddrs).and_return([ethernet])
        write_network_counters(receive: 100, transmit: 200)
      end

      def write_network_counters(receive:, transmit:)
        File.write(counters_file, "header\nheader\neth0: #{receive} 0 0 0 0 0 0 0 #{transmit} 0 0 0 0 0 0 0\n")
      end

      it 'reports byte deltas from a JSON round-tripped start snapshot' do
        previous = Gitlab::Json.generate(collector.snapshot)
        write_network_counters(receive: 150, transmit: 230)

        expect(collector.attributes(previous)).to include(
          "#{prefix}scope" => 'current_cgroup',
          'gitlab.cicd.network.receive_bytes' => 50,
          'gitlab.cicd.network.transmit_bytes' => 30,
          'gitlab.cicd.network.interface.name' => 'eth0'
        )
      end

      it 'keeps disk and cgroup attributes when the network observation is invalid', :aggregate_failures do
        allow(disk).to receive(:attributes).and_return('gitlab.cicd.disk.space_available_end_bytes' => 100)
        previous = Gitlab::Json.generate(collector.snapshot)
        write_network_counters(receive: 50, transmit: 230)

        attributes = collector.attributes(previous)

        expect(attributes).to include("#{prefix}memory_end_bytes" => 200,
          'gitlab.cicd.disk.space_available_end_bytes' => 100)
        expect(attributes.keys.grep(/\Agitlab\.cicd\.network\./)).to be_empty
      end
    end

    it 'combines network attributes without mutating the disk collector result', :aggregate_failures do
      disk_attributes = { 'gitlab.cicd.disk.space_available_end_bytes' => 100 }.freeze
      allow(disk).to receive(:attributes).and_return(disk_attributes)
      allow(network).to receive(:attributes).and_return('gitlab.cicd.network.receive_bytes' => 50)

      expect(collector.attributes(Gitlab::Json.generate(collector.snapshot))).to include(
        'gitlab.cicd.disk.space_available_end_bytes' => 100, 'gitlab.cicd.network.receive_bytes' => 50)
      expect(disk_attributes.keys).to eq(['gitlab.cicd.disk.space_available_end_bytes'])
    end

    it 'collects disk independently when cgroups are unavailable' do
      disk = instance_double(OtelSpanDiskUsage)
      allow(disk).to receive_messages(snapshot: { 'identity' => [1, 'abcd'] },
        attributes: { 'gitlab.cicd.disk.space_available_end_bytes' => 100 })
      collector = described_class.new(cgroup_file: '/missing/cgroup', disk: disk, network: network)

      expect(collector.attributes(Gitlab::Json.dump(collector.snapshot))).to eq(
        'gitlab.cicd.disk.space_available_end_bytes' => 100
      )
    end

    it 'reports numeric CPU deltas, memory boundaries, headroom and pressure event deltas' do
      previous = Gitlab::Json.generate(collector.snapshot)
      write_counters(directory, cpu: 1_500_100, memory: 400, limit: 800, events: 2)

      expect(collector.attributes(previous)).to include(
        "#{prefix}scope" => 'current_cgroup',
        "#{prefix}source" => 'cgroup_v2',
        "#{prefix}cpu_time_seconds" => 1.5,
        "#{prefix}memory_start_bytes" => 200,
        "#{prefix}memory_end_bytes" => 400,
        "#{prefix}memory_limit_start_bytes" => 1000,
        "#{prefix}memory_limit_end_bytes" => 800,
        "#{prefix}memory_headroom_start_bytes" => 800,
        "#{prefix}memory_headroom_end_bytes" => 400,
        "#{prefix}memory_events_high" => 2,
        "#{prefix}memory_events_max" => 2,
        "#{prefix}memory_events_oom" => 2,
        "#{prefix}memory_events_oom_kill" => 2
      )
    end

    it 'uses each ancestor own usage for shared headroom' do
      write_counters(mountpoint, memory: 900, limit: 1000)
      previous = Gitlab::Json.generate(collector.snapshot)
      write_counters(mountpoint, memory: 950, limit: 1000)

      expect(collector.attributes(previous)).to include(
        "#{prefix}memory_headroom_start_bytes" => 800,
        "#{prefix}memory_visible_ancestor_headroom_start_bytes" => 100,
        "#{prefix}memory_visible_ancestor_headroom_end_bytes" => 50
      )
    end

    it 'omits unlimited headroom without replacing it with host available memory' do
      write_counters(directory, limit: 'max')

      attributes = collector.attributes(Gitlab::Json.generate(collector.snapshot))

      expect(attributes).to include("#{prefix}memory_start_bytes" => 200)
      expect(attributes.keys).not_to include("#{prefix}memory_limit_start_bytes",
        "#{prefix}memory_headroom_start_bytes")
    end

    it 'keeps valid measurements when another counter is malformed or absent' do
      previous = Gitlab::Json.generate(collector.snapshot)
      File.write(File.join(directory, 'cpu.stat'), 'usage_usec invalid')
      File.unlink(File.join(directory, 'memory.events'))

      attributes = collector.attributes(previous)

      expect(attributes).to include("#{prefix}memory_end_bytes" => 200)
      expect(attributes.keys).not_to include("#{prefix}cpu_time_seconds", "#{prefix}memory_events_oom")
    end

    it 'omits deltas after counters reset' do
      write_counters(directory, cpu: 100, events: 10)
      previous = Gitlab::Json.generate(collector.snapshot)
      write_counters(directory, cpu: 50, events: 2)

      attributes = collector.attributes(previous)

      expect(attributes).to include("#{prefix}memory_end_bytes" => 200)
      expect(attributes.keys).not_to include("#{prefix}cpu_time_seconds", "#{prefix}memory_events_high")
    end

    it 'clamps headroom at zero when usage exceeds the limit' do
      write_counters(directory, memory: 1200)

      expect(collector.attributes(Gitlab::Json.generate(collector.snapshot))).to include(
        "#{prefix}memory_headroom_start_bytes" => 0
      )
    end

    it 'omits measurements when the process changes cgroup' do
      previous = Gitlab::Json.generate(collector.snapshot)
      File.write(cgroup_file, "0::/\n")

      expect(collector.attributes(previous)).to be_empty
    end

    context 'with invalid snapshot data' do
      where(:previous) { ['invalid', '[]', '{}', 'x' * (described_class::MAX_BYTES + 1)] }

      with_them do
        it 'returns no measurements' do
          expect(collector.attributes(previous)).to be_empty
        end
      end
    end

    context 'with measurements outside the OTLP integer range' do
      def finite_in_range?(attributes)
        attributes.values.all? do |value|
          case value
          when Integer then value.between?(0, described_class::MAX_INT64)
          when Float then value.finite?
          else true
          end
        end
      end

      it 'omits an out-of-range CPU counter and keeps the other measurements' do
        previous = Gitlab::Json.generate(collector.snapshot)
        File.write(File.join(directory, 'cpu.stat'), "usage_usec #{'9' * 400}\n")

        attributes = collector.attributes(previous)

        expect(attributes).to include("#{prefix}memory_end_bytes" => 200)
        expect(attributes.keys).not_to include("#{prefix}cpu_time_seconds")
        expect(finite_in_range?(attributes)).to be(true)
      end

      where(:overrides) do
        [
          [{ 'memory_bytes' => 1 << 63 }],
          [{ 'memory_limit_bytes' => 1 << 64 }],
          [{ 'cpu_usage_usec' => 1 << 64 }],
          [{ 'events' => { 'high' => 1 << 64 } }],
          [{ 'ancestors' => [{ 'memory_bytes' => 1, 'memory_limit_bytes' => 1 << 64 }] }]
        ]
      end

      with_them do
        it 'omits the affected previous measurement and keeps the current ones' do
          previous = Gitlab::Json.generate(collector.snapshot.merge(overrides))

          attributes = collector.attributes(previous)

          expect(attributes).to include("#{prefix}memory_end_bytes" => 200)
          expect(finite_in_range?(attributes)).to be(true)
        end
      end
    end

    context 'with a previous snapshot whose nested values have unexpected types' do
      where(:overrides) do
        [
          [{ 'events' => [] }],
          [{ 'events' => 'high' }],
          [{ 'ancestors' => 5 }],
          [{ 'ancestors' => ['text', nil, 3] }]
        ]
      end

      with_them do
        it 'ignores the malformed values and keeps the valid measurements' do
          previous = Gitlab::Json.generate(collector.snapshot.merge(overrides))

          expect(collector.attributes(previous)).to include("#{prefix}memory_end_bytes" => 200)
        end
      end
    end

    context 'when all cgroup counters are unavailable' do
      before do
        %w[cpu.stat memory.current memory.max memory.events].each do |filename|
          File.unlink(File.join(directory, filename))
        end
      end

      it 'omits the cgroup scope rather than reporting empty measurements' do
        expect(collector.attributes(Gitlab::Json.generate(collector.snapshot))).to be_empty
      end
    end
  end

  describe '#snapshot' do
    it 'maps a mounted subtree to process membership' do
      File.write(cgroup_file, "0::/parent/job\n")
      File.write(mountinfo_file, "1 2 0:1 /parent #{mountpoint} rw - cgroup2 cgroup rw\n")

      expect(collector.snapshot['memory_bytes']).to eq(200)
    end

    it 'handles a cgroup namespace root without traversing above its mount' do
      File.write(cgroup_file, "0::/\n")
      write_counters(mountpoint)

      expect(collector.snapshot).to include('memory_bytes' => 200, 'ancestors' => [])
    end

    it 'decodes escaped mount paths' do
      spaced_mountpoint = File.join(tmp_dir, 'with space')
      FileUtils.mkdir_p(File.join(spaced_mountpoint, 'job'))
      write_counters(File.join(spaced_mountpoint, 'job'))
      escaped = spaced_mountpoint.gsub(' ') { '\\040' }
      File.write(mountinfo_file, "1 2 0:1 / #{escaped} rw - cgroup2 cgroup rw\n")

      expect(collector.snapshot['memory_bytes']).to eq(200)
    end

    it 'does not select an unrelated mounted subtree' do
      File.write(mountinfo_file, "1 2 0:1 /other #{mountpoint} rw - cgroup2 cgroup rw\n")

      expect(collector.snapshot).to be_empty
    end

    it 'does not misattribute namespace-root membership to an unrelated bind mount' do
      File.write(cgroup_file, "0::/\n")
      write_counters(mountpoint, memory: 400)
      File.write(mountinfo_file, <<~MOUNTS)
        1 2 0:1 /other #{directory} rw - cgroup2 cgroup rw
        2 3 0:1 / #{mountpoint} rw - cgroup2 cgroup rw
      MOUNTS

      expect(collector.snapshot['memory_bytes']).to eq(400)
    end

    it 'accepts a namespace-root subtree only with evidence of process membership' do
      File.write(cgroup_file, "0::/\n")
      File.write(mountinfo_file, "1 2 0:1 /parent #{directory} rw - cgroup2 cgroup rw\n")
      File.write(File.join(directory, 'cgroup.procs'), "#{Process.pid}\n")

      expect(collector.snapshot['memory_bytes']).to eq(200)
    end

    context 'with an empty cgroup.procs file' do
      let(:disk) { instance_double(OtelSpanDiskUsage, snapshot: { 'identity' => [1, 'abcd'] }, attributes: {}) }

      before do
        File.write(cgroup_file, "0::/\n")
        File.write(mountinfo_file, "1 2 0:1 /parent #{directory} rw - cgroup2 cgroup rw\n")
        File.write(File.join(directory, 'cgroup.procs'), '')
      end

      it 'omits the cgroup measurements and keeps the disk snapshot' do
        expect(collector.snapshot).to eq('disk' => { 'identity' => [1, 'abcd'] })
      end
    end

    context 'with an empty counter file' do
      where(:filename, :key, :value) do
        [
          ['cpu.stat', 'cpu_usage_usec', nil],
          ['memory.current', 'memory_bytes', nil],
          ['memory.max', 'memory_limit_bytes', nil],
          ['memory.events', 'events', {}]
        ]
      end

      with_them do
        before do
          File.write(File.join(directory, filename), '')
        end

        it 'records that counter as unavailable instead of failing the snapshot' do
          expect(collector.snapshot).to include(key => value, 'identity' => be_present)
        end
      end
    end

    context 'when the disk snapshot times out' do
      let(:disk) { OtelSpanDiskUsage.new(project_dir: tmp_dir) }

      before do
        stub_const('RUBY_PLATFORM', 'x86_64-linux')
        allow(disk).to receive(:filesystem_stat).and_raise(OtelSpanDiskUsage::StatTimeout)
      end

      it 'keeps the cgroup measurements' do
        snapshot = collector.snapshot

        expect(snapshot).to include('memory_bytes' => 200)
        expect(snapshot).not_to have_key('disk')
      end
    end

    it 'does not guess host counters when membership contains parent traversal' do
      File.write(cgroup_file, "0::/../job\n")

      expect(collector.snapshot).to be_empty
    end

    it 'returns no snapshot for cgroup v1' do
      File.write(cgroup_file, "1:memory:/job\n")

      expect(collector.snapshot).to be_empty
    end

    it 'returns no snapshot when proc files are unavailable' do
      File.unlink(cgroup_file)

      expect(collector.snapshot).to be_empty
    end

    context 'with a missing cgroup directory' do
      before do
        File.write(cgroup_file, "0::/missing\n")
      end

      it 'returns no snapshot' do
        expect(collector.snapshot).to be_empty
      end
    end

    context 'with malformed or unrelated mount information' do
      where(:mountinfo) do
        ["malformed\n", "1 2 0:1 / /other rw - ext4 device rw\n",
          "1 2 0:1 - cgroup2 cgroup rw\n", "1 2 0:1 / - cgroup2 cgroup rw\n",
          "1 2 0:1 / /other rw - \n"]
      end

      with_them do
        before do
          File.write(mountinfo_file, mountinfo)
        end

        it 'returns no snapshot' do
          expect(collector.snapshot).to be_empty
        end
      end
    end

    context 'with a counter missing its value' do
      before do
        File.write(File.join(directory, 'cpu.stat'), "usage_usec\nuser_usec 50\n")
      end

      it 'retains independent measurements without guessing the CPU counter' do
        expect(collector.snapshot).to include('cpu_usage_usec' => nil, 'memory_bytes' => 200)
      end
    end

    context 'when an ancestor becomes unreadable' do
      before do
        allow(File).to receive(:stat).and_call_original
        allow(File).to receive(:stat).with(mountpoint).and_raise(Errno::EACCES)
      end

      it 'retains current-cgroup measurements' do
        expect(collector.snapshot).to include('memory_bytes' => 200, 'ancestors' => [])
      end
    end

    context 'when the cgroup disappears after discovery' do
      before do
        allow(File).to receive(:stat).and_call_original
        allow(File).to receive(:stat).with(directory).and_raise(Errno::ENOENT)
      end

      it 'returns no snapshot' do
        expect(collector.snapshot).to be_empty
      end
    end

    context 'when disk enrichment exceeds the snapshot bound' do
      before do
        allow(disk).to receive(:snapshot).and_return('oversized' => 'x' * described_class::MAX_BYTES)
      end

      it 'returns no snapshot' do
        expect(collector.snapshot).to be_empty
      end
    end

    context 'when cgroup measurements exceed the snapshot bound' do
      before do
        stub_const('OtelSpanResourceUsage::MAX_BYTES', 128)
      end

      it 'returns no snapshot' do
        expect(collector.snapshot).to be_empty
      end
    end
  end
end
