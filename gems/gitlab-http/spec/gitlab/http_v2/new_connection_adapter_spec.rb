# frozen_string_literal: true

require 'spec_helper'
require 'rspec-parameterized'

RSpec.describe Gitlab::HTTP_V2::NewConnectionAdapter, feature_category: :shared do
  using RSpec::Parameterized::TableSyntax

  include NextInstanceOf

  let(:uri) { URI('https://example.org') }
  let(:options) { {} }

  subject(:connection) { described_class.new(uri, options).connection }

  describe '#connection' do
    before do
      stub_all_dns('https://example.org', ip_address: '93.184.216.34')
    end

    context 'when local requests are allowed' do
      let(:options) { { allow_local_requests: true } }

      it 'sets up the connection' do
        expect(connection).to be_a(Gitlab::HTTP_V2::NetHttpAdapter)
        expect(connection.address).to eq('93.184.216.34')
        expect(connection.hostname_override).to eq('example.org')
        expect(connection.addr_port).to eq('example.org')
        expect(connection.port).to eq(443)
      end
    end

    context 'when local requests are not allowed' do
      let(:options) { { allow_local_requests: false } }

      it 'sets up the connection' do
        expect(connection).to be_a(Gitlab::HTTP_V2::NetHttpAdapter)
        expect(connection.address).to eq('93.184.216.34')
        expect(connection.hostname_override).to eq('example.org')
        expect(connection.addr_port).to eq('example.org')
        expect(connection.port).to eq(443)
      end

      context 'when it is a request to local network' do
        let(:uri) { URI('http://172.16.0.0/12') }

        it 'raises error' do
          expect { subject }.to raise_error(
            Gitlab::HTTP_V2::BlockedUrlError,
            "URL is blocked: Requests to the local network are not allowed"
          )
        end

        context 'when local request allowed' do
          let(:options) { { allow_local_requests: true } }

          it 'sets up the connection' do
            expect(connection).to be_a(Gitlab::HTTP_V2::NetHttpAdapter)
            expect(connection.address).to eq('172.16.0.0')
            expect(connection.hostname_override).to be(nil)
            expect(connection.addr_port).to eq('172.16.0.0')
            expect(connection.port).to eq(80)
          end
        end
      end

      context 'when it is a request to local address' do
        let(:uri) { URI('http://127.0.0.1') }

        it 'raises error' do
          expect { subject }.to raise_error(
            Gitlab::HTTP_V2::BlockedUrlError,
            "URL is blocked: Requests to localhost are not allowed"
          )
        end

        context 'when local request allowed' do
          let(:options) { { allow_local_requests: true } }

          it 'sets up the connection' do
            expect(connection).to be_a(Gitlab::HTTP_V2::NetHttpAdapter)
            expect(connection.address).to eq('127.0.0.1')
            expect(connection.hostname_override).to be(nil)
            expect(connection.addr_port).to eq('127.0.0.1')
            expect(connection.port).to eq(80)
          end
        end
      end

      context 'when port different from URL scheme is used' do
        let(:uri) { URI('https://example.org:8080') }

        it 'sets up the addr_port accordingly' do
          expect(connection).to be_a(Gitlab::HTTP_V2::NetHttpAdapter)
          expect(connection.address).to eq('93.184.216.34')
          expect(connection.hostname_override).to eq('example.org')
          expect(connection.addr_port).to eq('example.org:8080')
          expect(connection.port).to eq(8080)
        end
      end
    end

    context 'when DNS rebinding protection is disabled' do
      let(:options) { { dns_rebinding_protection_enabled: false } }

      it 'sets up the connection' do
        expect(connection).to be_a(Gitlab::HTTP_V2::NetHttpAdapter)
        expect(connection.address).to eq('example.org')
        expect(connection.hostname_override).to eq(nil)
        expect(connection.addr_port).to eq('example.org')
        expect(connection.port).to eq(443)
      end
    end

    context 'when proxy is enabled' do
      before do
        stub_env('https_proxy', 'http://proxy.example.com')
      end

      it 'proxy stays configured' do
        expect(connection.proxy?).to be true
        expect(connection.proxy_from_env?).to be true
        expect(connection.proxy_address).to eq('proxy.example.com')
      end

      context 'when no_proxy matches the request' do
        before do
          stub_env('no_proxy', 'example.org')
        end

        it 'proxy is disabled' do
          expect(connection.proxy?).to be false
          expect(connection.proxy_from_env?).to be false
          expect(connection.proxy_address).to be nil
        end
      end

      context 'when no_proxy does not match the request' do
        before do
          stub_env('no_proxy', 'example.com')
        end

        it 'proxy stays configured' do
          expect(connection.proxy?).to be true
          expect(connection.proxy_from_env?).to be true
          expect(connection.proxy_address).to eq('proxy.example.com')
        end
      end
    end

    context 'when URL scheme is not HTTP/HTTPS' do
      let(:uri) { URI('ssh://example.org') }

      it 'raises error' do
        expect { subject }.to raise_error(
          Gitlab::HTTP_V2::BlockedUrlError,
          "URL is blocked: Only allowed schemes are http, https"
        )
      end
    end

    context 'when the environment proxy is cached before it is disabled' do
      let(:uri) { URI("#{scheme}://example.org") }
      let(:proxy_url) { 'http://proxy.example.com:8080' }

      where(:scheme, :port) do
        'http'  | 80
        'https' | 443
      end

      with_them do
        before do
          stub_env("#{scheme}_proxy", proxy_url)
          stub_env('no_proxy', 'example.org')
        end

        it 'connects directly to the validated IP despite the cached proxy #security', :aggregate_failures do
          expect_next_instance_of(described_class, uri, options) do |adapter|
            # Resolve early, before the adapter restores the hostname and disables the proxy.
            expect(adapter).to receive(:attach_ssl_certificates).and_wrap_original do |original, http, http_options|
              original.call(http, http_options)
              expect(http.proxy_uri).to eq(URI(proxy_url))
            end
          end

          expect(connection.proxy_from_env?).to be false
          expect(connection.proxy?).to be false
          expect(connection.proxy_address).to be_nil

          expect(TCPSocket).to receive(:open).with('93.184.216.34', port, nil, nil)
            .and_raise(Errno::ECONNREFUSED)

          expect { connection.send(:connect) }.to raise_error(Errno::ECONNREFUSED)
        end
      end
    end

    describe 'candidate address exposure for connect-time fallback' do
      let(:uri) { URI('http://example.org') }
      let(:options) { { allow_local_requests: true } }

      def stub_resolved(*ips)
        addrs = ips.map { |ip| Addrinfo.tcp(ip, 80) }
        allow(Addrinfo).to receive(:getaddrinfo).and_call_original
        allow(Addrinfo).to receive(:getaddrinfo)
          .with('example.org', anything, anything, :STREAM, any_args)
          .and_return(addrs)
      end

      it 'caps to one address per family' do
        stub_resolved('2001:db8::1', '2001:db8::2', '198.51.100.1', '198.51.100.2')

        expect(connection.gitlab_candidate_addresses).to eq(['2001:db8::1', '198.51.100.1'])
      end

      it 'exposes a single address unchanged' do
        stub_resolved('198.51.100.1')

        expect(connection.gitlab_candidate_addresses).to eq(['198.51.100.1'])
      end

      context 'when the host is in the outbound allowlist' do
        let(:options) { super().merge(outbound_local_requests_allowlist: ['example.org']) }

        it 'exposes no candidates' do
          stub_resolved('198.51.100.1', '198.51.100.2')

          expect(connection.gitlab_candidate_addresses).to be_nil
        end
      end

      context 'when the host is in extra_allowed_uris' do
        let(:options) { super().merge(extra_allowed_uris: [uri]) }

        it 'exposes no candidates' do
          stub_resolved('198.51.100.1', '198.51.100.2')

          expect(connection.gitlab_candidate_addresses).to be_nil
        end
      end

      context 'when DNS rebinding protection is disabled' do
        let(:options) { { dns_rebinding_protection_enabled: false } }

        it 'exposes no candidates so the OS keeps selecting addresses' do
          stub_resolved('198.51.100.1', '198.51.100.2')

          expect(connection.gitlab_candidate_addresses).to be_nil
        end
      end
    end
  end
end
