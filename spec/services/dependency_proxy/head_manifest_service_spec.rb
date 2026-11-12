# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DependencyProxy::HeadManifestService, feature_category: :virtual_registry do
  include DependencyProxyHelpers
  using RSpec::Parameterized::TableSyntax

  let(:image) { 'alpine' }
  let(:tag) { 'latest' }
  let(:token) { Digest::SHA256.hexdigest('123') }
  let(:digest) { '12345' }
  let(:content_type) { 'foo' }
  let(:headers) do
    {
      DependencyProxy::Manifest::DIGEST_HEADER => digest,
      'content-type' => content_type
    }
  end

  subject(:result) { described_class.new(image, tag, token).execute }

  context 'remote request is successful' do
    before do
      stub_manifest_head(image, tag, headers: headers)
    end

    it { expect(subject[:status]).to eq(:success) }
    it { expect(subject[:digest]).to eq(digest) }
  end

  context 'remote request is not found' do
    before do
      stub_manifest_head(image, tag, status: 404, body: 'Not found')
    end

    it { expect(subject[:status]).to eq(:error) }
    it { expect(subject[:http_status]).to eq(404) }
    it { expect(subject[:message]).to eq('Not found') }
  end

  context 'net timeout exception' do
    before do
      manifest_link = DependencyProxy::Registry.manifest_url(image, tag)

      stub_full_request(manifest_link, method: :head).to_timeout
    end

    it { expect(subject[:status]).to eq(:error) }
    it { expect(subject[:http_status]).to eq(503) }
    it { expect(subject[:reason]).to eq(:upstream_request_failed) }
    it { expect(subject[:message]).to eq('execution expired') }
  end

  context 'when the registry responds with service unavailable' do
    before do
      stub_manifest_head(image, tag, status: 503, body: 'Service Unavailable')
    end

    it 'preserves the upstream response without marking it as a failed request', :aggregate_failures do
      expect(result).to include(status: :error, http_status: 503)
      expect(result[:reason]).to be_nil
    end
  end

  context 'when there is no token' do
    let(:token) { nil }

    before do
      stub_manifest_head(image, tag, headers: headers)
    end

    it 'omits the Authorization header instead of sending an empty bearer token' do
      subject

      manifest_url = DependencyProxy::Registry.manifest_url(image, tag)

      expect(
        a_request(:head, /#{Regexp.escape(URI(manifest_url).path)}/)
          .with { |req| req.headers.key?('Authorization') }
      ).not_to have_been_made
    end
  end

  context 'when the registry is unreachable' do
    where(:exception) { Gitlab::HTTP::HTTP_ERRORS }

    with_them do
      before do
        manifest_link = DependencyProxy::Registry.manifest_url(image, tag)

        stub_full_request(manifest_link, method: :head).to_raise(exception)
      end

      it { expect(subject[:status]).to eq(:error) }

      it { expect(result[:http_status]).to eq(503) }
      it { expect(result[:reason]).to eq(:upstream_request_failed) }

      it 'logs the exception with the image' do
        allow(Gitlab::ErrorTracking).to receive(:log_exception).and_call_original
        expect(Gitlab::ErrorTracking).to receive(:log_exception).with(an_instance_of(exception), { image: image })

        result
      end
    end
  end
end
