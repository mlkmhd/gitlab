# frozen_string_literal: true

require 'fast_spec_helper'
require 'faraday'

RSpec.describe ArtifactRegistry::Resources::Base, :aggregate_failures, feature_category: :artifact_registry do
  subject(:resource) { resource_class.new(transport: transport, reporting: reporting) }

  let(:resource_class) do
    Class.new(described_class) do
      public(*(ArtifactRegistry::Resources::Base.private_instance_methods(false) - [:initialize]))
    end
  end

  let(:transport) { instance_double(ArtifactRegistry::Transport) }
  let(:reporting) { instance_double(ArtifactRegistry::Reporting) }
  let(:unexpected_success) { ArtifactRegistry::Errors::UnavailableError.new('unexpected success') }

  def stub_raise_terminal
    allow(reporting).to receive(:raise_terminal).and_raise(unexpected_success)
  end

  describe 'public interface' do
    it 'defines no public methods, so a resource exposes only its endpoints' do
      expect(described_class.public_instance_methods(false)).to be_empty
    end
  end

  describe 'request forwarding' do
    let(:response) { Faraday::Response.new(method: :get, status: 200, body: {}) }

    context 'with a per-user request' do
      before do
        allow(transport).to receive(:user_request).and_return(response)
      end

      it 'sends it through the transport and returns its response' do
        expect(resource.user_request(:get, 'api/v1/my-group', slug: 'my-group', query: { limit: 1 })).to be(response)
        expect(transport).to have_received(:user_request)
          .with(:get, 'api/v1/my-group', slug: 'my-group', query: { limit: 1 })
      end
    end

    context 'with a service request' do
      before do
        allow(transport).to receive(:service_request).and_return(response)
      end

      it 'sends it through the transport and returns its response' do
        expect(resource.service_request(:post, 'api/gitlab/v1/namespaces', body: { slug: 'my-group' }))
          .to be(response)
        expect(transport).to have_received(:service_request)
          .with(:post, 'api/gitlab/v1/namespaces', body: { slug: 'my-group' })
      end
    end
  end

  describe 'reporting forwarding' do
    let(:error) { ArtifactRegistry::Errors::ApiError.new('not found', status: 404) }

    context 'when logging an error' do
      before do
        allow(reporting).to receive(:log_error)
      end

      it 'logs it through the reporting object with the context' do
        resource.log_error(error, slug: 'my-group')

        expect(reporting).to have_received(:log_error).with(error, slug: 'my-group')
      end
    end

    context 'when raising a terminal error' do
      before do
        stub_raise_terminal
      end

      it 'raises through the reporting object with the context' do
        expect { resource.raise_terminal(ArtifactRegistry::Errors::UnavailableError, 'boom', :get, slug: 'my-group') }
          .to raise_error(unexpected_success)
        expect(reporting).to have_received(:raise_terminal)
          .with(ArtifactRegistry::Errors::UnavailableError, 'boom', :get, slug: 'my-group')
      end
    end
  end

  describe '#nil_on_missing' do
    before do
      allow(reporting).to receive(:log_error)
    end

    context 'when the block returns' do
      it 'returns the block value without logging' do
        expect(resource.nil_on_missing(log: true, slug: 'my-group') { :found }).to eq(:found)
        expect(reporting).not_to have_received(:log_error)
      end
    end

    context 'when the block raises a 404' do
      let(:error) { ArtifactRegistry::Errors::ApiError.new('not found', status: 404) }

      it 'returns nil without logging by default' do
        expect(resource.nil_on_missing(slug: 'my-group') { raise error }).to be_nil
        expect(reporting).not_to have_received(:log_error)
      end

      it 'returns nil and logs the error with the context when log is true' do
        expect(resource.nil_on_missing(log: true, slug: 'my-group') { raise error }).to be_nil
        expect(reporting).to have_received(:log_error).with(error, slug: 'my-group')
      end
    end

    context 'when the block raises another API error' do
      let(:error) { ArtifactRegistry::Errors::ApiError.new('bad request', status: 400) }

      it 're-raises it without logging' do
        expect { resource.nil_on_missing(log: true, slug: 'my-group') { raise error } }.to raise_error(error)
        expect(reporting).not_to have_received(:log_error)
      end
    end
  end

  describe '#success_body' do
    before do
      stub_raise_terminal
    end

    context 'when the body has the expected class' do
      let(:response) { Faraday::Response.new(method: :get, status: 200, body: { 'id' => 'a1' }) }

      it 'returns the body' do
        expect(resource.success_body(response, expected: Hash, slug: 'my-group')).to eq({ 'id' => 'a1' })
        expect(reporting).not_to have_received(:raise_terminal)
      end
    end

    context 'when the body has another class' do
      let(:response) { Faraday::Response.new(method: :get, status: 200, body: []) }

      it 'raises an unexpected success with the attribution' do
        expect { resource.success_body(response, expected: Hash, slug: 'my-group') }
          .to raise_error(unexpected_success)
        expect(reporting).to have_received(:raise_terminal).with(
          ArtifactRegistry::Errors::UnavailableError,
          'Artifact Registry returned an unexpected success response',
          :get,
          status: 200, body_class: 'Array', slug: 'my-group'
        )
      end
    end
  end

  describe '#list_rows' do
    before do
      stub_raise_terminal
    end

    context 'when the body is an array of objects' do
      let(:response) { Faraday::Response.new(method: :get, status: 200, body: [{ 'id' => 'a1' }]) }

      it 'returns the rows' do
        expect(resource.list_rows(response, slug: 'my-group')).to eq([{ 'id' => 'a1' }])
      end
    end

    context 'when a row is not an object' do
      let(:response) { Faraday::Response.new(method: :get, status: 200, body: [{ 'id' => 'a1' }, 'oops']) }

      it 'raises an unexpected success attributed to the slug' do
        expect { resource.list_rows(response, slug: 'my-group') }.to raise_error(unexpected_success)
        expect(reporting).to have_received(:raise_terminal).with(
          ArtifactRegistry::Errors::UnavailableError,
          'Artifact Registry returned an unexpected success response',
          :get,
          status: 200, body_class: 'Array', slug: 'my-group'
        )
      end
    end

    context 'when the body is not an array' do
      let(:response) { Faraday::Response.new(method: :get, status: 200, body: {}) }

      it 'raises an unexpected success' do
        expect { resource.list_rows(response, slug: 'my-group') }.to raise_error(unexpected_success)
        expect(reporting).to have_received(:raise_terminal).with(
          ArtifactRegistry::Errors::UnavailableError,
          'Artifact Registry returned an unexpected success response',
          :get,
          status: 200, body_class: 'Hash', slug: 'my-group'
        )
      end
    end
  end

  describe '#permissions_query' do
    it 'asks for permissions only when they are requested' do
      expect(resource.permissions_query(true)).to eq({ include_permissions: true })
      expect(resource.permissions_query(false)).to eq({})
    end
  end

  describe '#verdicts' do
    context 'when permissions were not requested' do
      it 'returns nil' do
        expect(resource.verdicts({}, scope: :repository, read: :repositories, slug: 'my-group', requested: false))
          .to be_nil
      end
    end

    context 'when the permissions are not an object' do
      it 'returns an absent verdict carrying the scope, read and slug' do
        result = resource.verdicts([true], scope: :repository, read: :repositories, slug: 'my-group', requested: true)

        expect(result).to be_absent
        expect(result).to have_attributes(scope: :repository, read: :repositories, slug: 'my-group')
      end
    end

    context 'when the permissions are an object' do
      it 'returns the verdicts for its scope, carrying the read and slug' do
        result = resource.verdicts({ 'delete_artifact' => true, 'create_repository' => true },
          scope: :repository, read: :repositories, slug: 'my-group', requested: true)

        expect(result).to be_a(ArtifactRegistry::Permissions::Verdicts)
        expect(result).not_to be_absent
        expect(result).to have_attributes(scope: :repository, read: :repositories, slug: 'my-group')
        expect(result.allowed?('delete_artifact')).to be(true)
        expect(result.allowed?('create_repository')).to be(false)
      end
    end
  end

  describe '#raise_unexpected_success' do
    before do
      stub_raise_terminal
    end

    context 'with a finished response' do
      let(:response) { Faraday::Response.new(method: :delete, status: 200, body: '{}') }

      it 'raises through the reporting object with the method, status, body class and attribution' do
        expect { resource.raise_unexpected_success(response, slug: 'my-group') }.to raise_error(unexpected_success)
        expect(reporting).to have_received(:raise_terminal).with(
          ArtifactRegistry::Errors::UnavailableError,
          'Artifact Registry returned an unexpected success response',
          :delete,
          status: 200, body_class: 'String', slug: 'my-group'
        )
      end
    end

    context 'with a response that carries no env' do
      let(:response) { Faraday::Response.new }

      it 'raises with no method or status' do
        expect { resource.raise_unexpected_success(response, slug: 'my-group') }.to raise_error(unexpected_success)
        expect(reporting).to have_received(:raise_terminal).with(
          ArtifactRegistry::Errors::UnavailableError,
          'Artifact Registry returned an unexpected success response',
          nil,
          status: nil, body_class: 'NilClass', slug: 'my-group'
        )
      end
    end
  end
end
