# frozen_string_literal: true

require 'fast_spec_helper'
require 'tmpdir'
require_relative '../../../scripts/ci/otel_span_network_usage'

RSpec.describe OtelSpanNetworkUsage, feature_category: :tooling do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:counters_file) { File.join(tmp_dir, 'dev') }
  let(:namespace_file) { File.join(tmp_dir, 'namespace') }
  let(:collector) { described_class.new(counters_file: counters_file, namespace_file: namespace_file) }
  # Flags captured on Linux: UP,LOOPBACK,RUNNING,LOWER_UP and UP,BROADCAST,RUNNING,MULTICAST,LOWER_UP.
  # Hex literals avoid IFF_MULTICAST differing across platforms and IFF_LOWER_UP missing from some Ruby builds.
  # The loopback is named `local` to prove that it is detected by its flag, not its name.
  let(:loopback) { instance_double(Socket::Ifaddr, name: 'local', ifindex: 1, flags: 0x10049) }
  let(:ethernet) { instance_double(Socket::Ifaddr, name: 'eth0', ifindex: 2, flags: 0x11043) }
  # An inactive NOARP tunnel, which Linux adds to every network namespace when the ipip module is loaded.
  let(:tunnel) { instance_double(Socket::Ifaddr, name: 'tunl0', ifindex: 3, flags: 0x80) }
  let(:interfaces) { [loopback, ethernet, ethernet] }
  let(:counter_names) { %w[local eth0] }
  let(:receive_bytes) { 100 }
  let(:transmit_bytes) { 200 }
  let(:text) { counters_text(counter_names) }

  # Mirrors `/proc/net/dev`, which right-aligns interface names in a six-character column.
  def counters_text(names)
    rows = names.map do |name|
      receive, transmit = name == 'eth0' ? [receive_bytes, transmit_bytes] : [10, 20]
      "#{name.rjust(6)}: #{receive} 1 0 0 0 0 0 0 #{transmit} 2 0 0 0 0 0 0"
    end

    <<~COUNTERS
      Inter-|   Receive                                                |  Transmit
       face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
      #{rows.join("\n")}
    COUNTERS
  end

  before do
    stub_const('RUBY_PLATFORM', 'x86_64-linux')
    File.write(namespace_file, '')
    File.write(counters_file, text)
    allow(Socket).to receive(:getifaddrs).and_return(interfaces)
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe '#snapshot' do
    subject(:snapshot) { collector.snapshot }

    it 'parses right-aligned counters, deduplicates addresses, and excludes loopback by flag' do
      stat = File.stat(namespace_file)

      expect(snapshot).to eq(
        'identity' => [[stat.dev, stat.ino], [['eth0', 2, false, true], ['local', 1, true, true]]],
        'interface_name' => 'eth0',
        'receive_bytes' => 100,
        'transmit_bytes' => 200
      )
    end

    context 'with an inactive interface' do
      let(:interfaces) { [loopback, ethernet, tunnel] }
      let(:counter_names) { %w[local eth0 tunl0] }

      it 'selects the active interface and keeps the inactive one in the identity', :aggregate_failures do
        expect(snapshot).to include('interface_name' => 'eth0', 'receive_bytes' => 100, 'transmit_bytes' => 200)
        expect(snapshot['identity'].last).to include(['tunl0', 3, false, false])
      end
    end

    context 'on an unsupported platform' do
      before do
        stub_const('RUBY_PLATFORM', 'arm64-darwin')
      end

      it 'omits measurements' do
        expect(snapshot).to be_empty
      end
    end

    context 'with only a loopback interface' do
      let(:interfaces) { [loopback] }
      let(:counter_names) { %w[local] }

      it 'omits measurements' do
        expect(snapshot).to be_empty
      end
    end

    context 'when the only non-loopback interface is inactive' do
      let(:interfaces) { [loopback, instance_double(Socket::Ifaddr, name: 'eth0', ifindex: 2, flags: 0x1002)] }

      it 'omits measurements' do
        expect(snapshot).to be_empty
      end
    end

    context 'with multiple active non-loopback interfaces' do
      let(:interfaces) { [loopback, ethernet, instance_double(Socket::Ifaddr, name: 'eth1', ifindex: 4, flags: 0x11043)] }
      let(:counter_names) { %w[local eth0 eth1] }

      it 'omits measurements' do
        expect(snapshot).to be_empty
      end
    end

    context 'when the counter inventory does not match the interface inventory' do
      where(:interfaces, :counter_names) do
        [
          [[ref(:loopback), ref(:ethernet), ref(:tunnel)], %w[local eth0]],
          [[ref(:loopback), ref(:ethernet)], %w[local eth0 tunl0]]
        ]
      end

      with_them do
        it 'omits measurements' do
          expect(snapshot).to be_empty
        end
      end
    end

    context 'with invalid or incomplete counters' do
      where(:text) { ['', 'invalid', "header\nheader\neth0: invalid\n", "header\nheader\n"] }

      with_them do
        it 'omits measurements' do
          expect(snapshot).to be_empty
        end
      end
    end

    context 'with a counters file at the size bound' do
      where(:size_delta, :measured) { [[0, true], [-1, false]] }

      with_them do
        before do
          stub_const('OtelSpanNetworkUsage::MAX_BYTES', text.bytesize + size_delta)
        end

        it 'reads only files within the bound' do
          expect(snapshot.key?('receive_bytes')).to be(measured)
        end
      end
    end

    context 'when interface inventory changes during sampling' do
      before do
        allow(Socket).to receive(:getifaddrs).and_return(interfaces, [loopback])
      end

      it 'omits measurements' do
        expect(snapshot).to be_empty
      end
    end

    context 'when counters are unavailable' do
      before do
        File.unlink(counters_file)
      end

      it 'omits measurements' do
        expect(snapshot).to be_empty
      end
    end
  end

  describe '#attributes' do
    subject(:attributes) { collector.attributes(previous, current) }

    let(:previous) { collector.snapshot }
    let(:current) { previous.merge('receive_bytes' => receive_end, 'transmit_bytes' => transmit_end) }
    let(:receive_end) { 150 }
    let(:transmit_end) { 275 }

    it 'reports received and transmitted interval deltas' do
      expect(attributes).to eq('gitlab.cicd.network.scope' => 'current_network_namespace',
        'gitlab.cicd.network.interface.name' => 'eth0',
        'gitlab.cicd.network.receive_bytes' => 50, 'gitlab.cicd.network.transmit_bytes' => 75)
    end

    context 'with zero traffic' do
      let(:receive_end) { 100 }
      let(:transmit_end) { 200 }

      it 'reports zero deltas' do
        expect(attributes).to include('gitlab.cicd.network.receive_bytes' => 0,
          'gitlab.cicd.network.transmit_bytes' => 0)
      end
    end

    context 'with an invalid end counter' do
      let(:current) { previous.merge(key => value) }

      where(:key, :value) do
        %w[receive_bytes transmit_bytes].product([99, -1, nil, '250', 1 << 63, (1 << 64) - 1, 10**400])
      end

      with_them do
        it 'omits all network attributes' do
          expect(attributes).to be_empty
        end
      end
    end

    context 'with an invalid start counter and a valid end counter' do
      let(:previous) { collector.snapshot.merge(key => value) }
      let(:current) { collector.snapshot }

      where(:key, :value) do
        %w[receive_bytes transmit_bytes].product([-5, nil, '1', 1 << 63])
      end

      with_them do
        it 'omits all network attributes' do
          expect(attributes).to be_empty
        end
      end
    end

    context 'when only the namespace changes' do
      let(:other_namespace_file) { File.join(tmp_dir, 'other_namespace') }
      let(:current) { described_class.new(counters_file: counters_file, namespace_file: other_namespace_file).snapshot }

      before do
        File.write(other_namespace_file, '')
      end

      it 'omits measurements', :aggregate_failures do
        expect(current['identity'].last).to eq(previous['identity'].last)
        expect(attributes).to be_empty
      end
    end

    context 'when only the interface inventory changes' do
      let(:recreated_ethernet) { instance_double(Socket::Ifaddr, name: 'eth0', ifindex: 5, flags: 0x11043) }
      let(:previous) do
        allow(Socket).to receive(:getifaddrs).and_return(interfaces)
        collector.snapshot
      end

      let(:current) do
        allow(Socket).to receive(:getifaddrs).and_return([loopback, recreated_ethernet])
        collector.snapshot
      end

      it 'omits measurements', :aggregate_failures do
        expect(previous['identity'].first).to eq(current['identity'].first)
        expect(attributes).to be_empty
      end
    end

    context 'without network data in one snapshot' do
      let(:snapshot) { collector.snapshot }

      where(:previous, :current) do
        [
          [nil, ref(:snapshot)],
          [ref(:snapshot), nil],
          [ref(:snapshot), {}]
        ]
      end

      with_them do
        it 'omits measurements' do
          expect(attributes).to be_empty
        end
      end
    end
  end
end
