# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::Resources::Upstreams, :aggregate_failures, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  include_context 'with an Artifact Registry resource'

  describe '#upstream_repositories' do
    let(:format) { 'maven' }
    let(:http_method) { :get }
    let(:request_url) { "#{repository_url}/#{format}/upstream_repositories" }
    let(:perform) { perform_with }

    let(:list_response) do
      [
        association_response(id: 'a1b2c3d4-0000-0000-0000-000000000000', position: 1,
          upstream_id: 'b1000000-0000-0000-0000-000000000000', upstream_name: 'payment-core', kind: 'hosted',
          visibility: 'public', size_bytes: 0),
        association_response(id: 'a2b3c4d5-0000-0000-0000-000000000000', position: 2,
          upstream_id: 'b2000000-0000-0000-0000-000000000000', upstream_name: 'payment-mirror', kind: 'remote',
          settings: { 'url' => 'https://repo.example.com/maven2', 'last_health_status' => 'healthy' })
      ]
    end

    def association_response(
      id:, position:, upstream_id:, upstream_name:, kind:,
      visibility: 'private', size_bytes: 4096, settings: nil)
      summary = {
        'id' => upstream_id,
        'name' => upstream_name,
        'format' => format,
        'kind' => kind,
        'visibility' => visibility,
        'size_bytes' => size_bytes,
        'settings' => settings
      }

      { 'id' => id, 'position' => position, 'upstream_repository' => summary.compact }
    end

    def perform_with(**arguments)
      client.upstream_repositories(slug: slug, repository_name: name, format: format, **arguments)
    end

    def with_upstream_permissions(row, permissions)
      row.merge('upstream_repository' => row['upstream_repository'].merge('permissions' => permissions))
    end

    context 'with a populated upstream list' do
      where(:format) { %w[maven npm docker oci] }

      with_them do
        it 'reads under the format upstream_repositories segment and returns association value objects',
          :aggregate_failures do
          request = stub_ar_list(body: list_response.to_json)

          result = perform
          upstreams = result.map(&:upstream_repository)

          expect(request).to have_been_requested
          expect(result).to be_an(Array)
          expect(result).to all(be_a(ArtifactRegistry::UpstreamRepositoryAssociation))
          expect(result.map(&:id)).to eq(
            %w[a1b2c3d4-0000-0000-0000-000000000000 a2b3c4d5-0000-0000-0000-000000000000]
          )
          expect(result.map(&:position)).to eq([1, 2])
          expect(upstreams.map(&:name)).to eq(%w[payment-core payment-mirror])
          expect(upstreams.map(&:kind)).to eq(%w[hosted remote])
          expect(upstreams.map(&:format)).to all(eq(format))
          expect(upstreams.map(&:visibility)).to eq(%w[public private])
          expect(upstreams.map(&:size_bytes)).to eq([0, 4096])
          expect(upstreams.map(&:settings)).to eq(
            [nil, { 'url' => 'https://repo.example.com/maven2', 'last_health_status' => 'healthy' }]
          )
        end
      end
    end

    it 'returns every element in AR order and hands back a bare array with no cursors', :aggregate_failures do
      ordered = Array.new(20) do |index|
        position = index + 1
        suffix = position.to_s.rjust(2, '0')
        association_response(id: "a#{suffix}00000-0000-0000-0000-000000000000", position: position,
          upstream_id: "b#{suffix}00000-0000-0000-0000-000000000000",
          upstream_name: "upstream-#{position}", kind: 'hosted')
      end
      stub_ar_list(body: ordered.to_json)

      result = perform

      expect(result.size).to eq(20)
      expect(result).not_to respond_to(:next_cursor)
      expect(result.map(&:position)).to eq((1..20).to_a)
    end

    it 'returns an empty array for a virtual repository with no upstreams' do
      stub_ar_list(body: [].to_json)

      expect(perform).to eq([])
    end

    it 'sends no include_permissions and exposes nil upstream permissions by default, whatever the rows carry',
      :aggregate_failures do
      stub_ar_list(body: list_response.map { |row| with_upstream_permissions(row, repository_permissions) }.to_json)

      result = perform

      expect(a_request(:get, request_url).with { |req| req.uri.query.blank? }).to have_been_made
      expect(result.map { |association| association.upstream_repository.permissions }).to eq([nil, nil])
    end

    context 'with include_permissions: true' do
      let(:perform) { perform_with(include_permissions: true) }

      def stub_ar_list_with_permissions(body)
        stub_request(:get, request_url)
          .with(query: { include_permissions: 'true' })
          .to_return(status: 200, body: body.to_json, headers: json_headers)
      end

      def upstream_permissions
        perform.map { |association| association.upstream_repository.permissions }
      end

      it 'sends include_permissions=true and exposes each row the verdicts on its own upstream repository',
        :aggregate_failures do
        request = stub_ar_list_with_permissions([
          with_upstream_permissions(list_response.first, repository_permissions),
          with_upstream_permissions(list_response.second,
            repository_permissions.merge('update_repository' => false, 'delete_artifact' => false))
        ])

        permissions = upstream_permissions

        expect(request).to have_been_requested
        expect(permissions).to all(be_a(ArtifactRegistry::Permissions::Verdicts))
        expect(permissions).to all(be_complete)
        expect(permissions.map { |verdicts| verdicts.allowed?('update_repository') }).to eq([true, false])
        expect(permissions.map { |verdicts| verdicts.allowed?('delete_artifact') }).to eq([true, false])
        expect(permissions.map { |verdicts| verdicts.allowed?('delete_repository') }).to eq([false, false])
        expect(permissions.map(&:read)).to eq(%i[upstream_repositories upstream_repositories])
        expect(permissions.map(&:slug)).to eq(%w[my-group my-group])
      end

      it 'exposes an absent verdict carrying the read and slug when a row upstream has no permissions object',
        :aggregate_failures do
        stub_ar_list_with_permissions(list_response)

        permissions = upstream_permissions

        expect(permissions).to all(be_absent)
        expect(permissions.map(&:read)).to eq(%i[upstream_repositories upstream_repositories])
        expect(permissions.map(&:slug)).to eq(%w[my-group my-group])
      end

      it 'reports a row as incomplete when an action of the repository set is missing', :aggregate_failures do
        stub_ar_list_with_permissions([
          with_upstream_permissions(list_response.first, repository_permissions.except('delete_artifact'))
        ])

        permissions = upstream_permissions.first

        expect(permissions).not_to be_complete
        expect(permissions.missing_actions).to eq(%w[delete_artifact])
      end

      it 'treats a permissions value that is not an object as absent' do
        stub_ar_list_with_permissions([with_upstream_permissions(list_response.first, [true])])

        expect(upstream_permissions).to all(be_absent)
      end

      it 'treats an upstream repository that is not an object as carrying absent verdicts', :aggregate_failures do
        stub_ar_list_with_permissions([list_response.first.merge('upstream_repository' => 'not-a-hash')])

        result = perform

        expect(result.size).to eq(1)
        expect(result.first.upstream_repository.permissions).to be_absent
      end
    end

    context 'when AR returns 404' do
      it 'returns nil rather than raising, covering a missing, non-virtual, or unseen repository' do
        stub_request(:get, request_url)
          .to_return(status: 404, body: error_envelope(code: 'not_found').to_json, headers: json_headers)

        expect(perform).to be_nil
      end

      it 'logs the envelope, so a path that drifted from AR is still diagnosable', :aggregate_failures do
        stub_request(:get, request_url).to_return(
          status: 404,
          body: error_envelope(code: 'not_found', message: 'repository not found', request_id: 'req-404').to_json,
          headers: json_headers
        )

        expect(Gitlab::ErrorTracking).to receive(:log_exception)
          .with(an_instance_of(described_class::ApiError),
            hash_including(url: base_url, slug: slug)) do |error, _context|
          expect(error.status).to eq(404)
          expect(error.code).to eq('not_found')
          expect(error.request_id).to eq('req-404')
        end

        expect(perform).to be_nil
      end
    end

    context 'when AR returns a mapped error status' do
      where(:status, :error_class) do
        401 | described_class::AuthorizationError
        403 | described_class::AuthorizationError
        429 | described_class::UnavailableError
        500 | described_class::UnavailableError
        503 | described_class::UnavailableError
      end

      with_them do
        it 'raises the mapped exception and preserves the envelope request_id and status', :aggregate_failures do
          stub_request(:get, request_url).to_return(
            status: status, body: error_envelope(request_id: 'req-upstream-id').to_json, headers: json_headers
          )

          expect { perform }.to raise_error(error_class) do |error|
            expect(error.request_id).to eq('req-upstream-id')
            expect(error.status).to eq(status)
          end
        end
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it_behaves_like 'rejecting an unexpected success body', status: 204, body: '', body_class: 'NilClass'
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '{}', body_class: 'Hash'
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '["oops"]', body_class: 'Array'
    end

    it 'attaches the credential as a Bearer header, never in the request URI', :aggregate_failures do
      request = stub_request(:get, request_url)
        .with(headers: { 'Authorization' => "Bearer #{token}" })
        .to_return(status: 200, body: list_response.to_json, headers: json_headers)

      perform

      expect(request).to have_been_requested
      expect(a_request(:get, request_url).with { |req| req.uri.to_s.exclude?(token) }).to have_been_made
    end

    context 'when the format is not one the client lists' do
      where(:format) { [nil, '', 'not-a-format'] }

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end

    context 'when slug or the repository name is blank or a bare dot-segment' do
      where(:slug, :name) do
        ''         | 'my-repo'
        '..'       | 'my-repo'
        'my-group' | '..'
      end

      with_them do
        it_behaves_like 'rejecting an invalid argument before any request'
      end
    end

    context 'when the slug and repository name contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }

      it 'percent-encodes each path segment so a value cannot smuggle extra path segments', :aggregate_failures do
        encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/upstream_repositories"
        encoded = stub_request(:get, "#{base_url}/api/v1/#{encoded_path}")
          .to_return(status: 200, body: list_response.to_json, headers: json_headers)
        traversed = stub_request(:get,
          "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/upstream_repositories")

        perform

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end
  end

  describe '#dissociate_upstream_repository' do
    let(:format) { 'maven' }
    let(:association_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:delete_url) { "#{repository_url}/#{format}/upstream_repositories/#{association_id}" }

    def perform
      client.dissociate_upstream_repository(
        slug: slug, repository_name: name, format: format, association_id: association_id
      )
    end

    def stub_dissociate(status:, body: '')
      stub_request(:delete, delete_url).to_return(status: status, body: body, headers: json_headers)
    end

    context 'when AR removes the association' do
      where(:format) { %w[maven npm docker oci] }

      with_them do
        it 'issues the delete under the format upstream_repositories member route and returns true',
          :aggregate_failures do
          request = stub_request(:delete, delete_url)
            .with(headers: { 'Authorization' => "Bearer #{token}" })
            .to_return(status: 204, body: '', headers: json_headers)

          expect(perform).to be(true)
          expect(request).to have_been_requested
        end
      end
    end

    context 'when the association is already gone (404)' do
      it 'returns true and reports the drift, covering a missing, non-virtual, or unseen repository',
        :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_dissociate(status: 404, body: error_envelope(code: 'not_found').to_json)

        expect(perform).to be(true)
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
          instance_of(described_class::ApiError),
          hash_including(method: :delete, code: 'not_found', status: 404, slug: slug,
            path: "api/v1/#{slug}/repositories/#{name}/#{format}/upstream_repositories/#{association_id}")
        )
      end

      it 'raises ApiError when the 404 body carries no error envelope', :aggregate_failures do
        stub_dissociate(status: 404, body: '')

        expect { perform }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(404)
          expect(error.code).to be_nil
        end
      end
    end

    context 'when AR refuses the write (401 and 403)' do
      where(:status) { [401, 403] }

      with_them do
        it 'raises AuthorizationError, not ApiError, and reports the auth failure once', :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_dissociate(status: status, body: error_envelope(code: 'forbidden').to_json)

          expect { perform }.to raise_error(described_class::AuthorizationError) do |error|
            expect(error.status).to eq(status)
            expect(error).not_to be_a(described_class::ApiError)
          end
          expect_auth_failure_reported_once(status)
        end
      end
    end

    context 'when AR cannot answer the delete (500 and 503)' do
      where(:status) { [500, 503] }

      with_them do
        it 'raises UnavailableError and redacts an echoed credential', :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          echoed = "rejected: Authorization: Bearer #{jwt_credential}"
          stub_dissociate(status: status, body: error_envelope(message: echoed).to_json)

          expect { perform }.to raise_error(described_class::UnavailableError) do |error|
            expect(error.message).to include('Bearer [REDACTED]')
            expect(error.message).not_to include(jwt_credential)
          end
        end
      end
    end

    context 'when AR answers a 2xx the contract does not allow' do
      where(:status) { [200, 202] }

      with_them do
        it 'raises UnavailableError rather than reading another 2xx as a removal' do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_dissociate(status: status, body: '{}')

          expect { perform }.to raise_error(described_class::UnavailableError, /unexpected success response/)
        end
      end
    end

    context 'when the format is not an artifact format' do
      where(:format) { ['conda', 'helm', ''] }

      with_them do
        it 'raises ArgumentError naming the artifact formats, before any request', :aggregate_failures do
          expect { perform }.to raise_error(ArgumentError, 'format must be one of: maven, npm, docker, oci')
          expect(token_exchange).not_to have_received(:token_for)
          expect(a_request(:any, %r{\A#{Regexp.escape(base_url)}})).not_to have_been_made
        end
      end
    end

    context 'when slug, the repository name, or the association id is blank or a bare dot-segment' do
      where(:slug, :name, :association_id) do
        ''         | 'my-repo' | 'a1b2c3d4-0000-0000-0000-000000000000'
        '..'       | 'my-repo' | 'a1b2c3d4-0000-0000-0000-000000000000'
        'my-group' | '..'      | 'a1b2c3d4-0000-0000-0000-000000000000'
        'my-group' | 'my-repo' | nil
        'my-group' | 'my-repo' | '..'
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          expect { perform }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
          expect(a_request(:any, %r{\A#{Regexp.escape(base_url)}})).not_to have_been_made
        end
      end

      context 'when the association id is blank' do
        let(:association_id) { '' }

        it 'names association_id and sends nothing at the collection route', :aggregate_failures do
          request = stub_request(:delete, "#{repository_url}/#{format}/upstream_repositories/")

          expect { perform }.to raise_error(ArgumentError, 'association_id is required')
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when the association id is not a UUID' do
      let(:association_id) { 'not-a-uuid' }

      it 'issues the delete rather than asserting a syntax the contract does not', :aggregate_failures do
        request = stub_dissociate(status: 204)

        expect(perform).to be(true)
        expect(request).to have_been_requested
      end
    end

    context 'when the slug, the repository name, and the association id contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }
      let(:association_id) { 'a/b' }

      it 'percent-encodes each path segment so a value cannot smuggle extra path segments',
        :aggregate_failures do
        encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/upstream_repositories/a%2Fb"
        encoded = stub_request(:delete, "#{base_url}/api/v1/#{encoded_path}")
          .to_return(status: 204, body: '', headers: json_headers)
        traversed = stub_request(:delete,
          "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/upstream_repositories/a/b")

        perform

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when a transport failure occurs on the DELETE' do
      before do
        stub_const('ArtifactRegistry::Transport::RETRY_OPTIONS', retry_options)
      end

      it 'does not retry and issues the DELETE exactly once', :aggregate_failures do
        stub_request(:delete, delete_url).to_timeout

        expect { perform }.to raise_error(described_class::UnavailableError)
        expect(a_request(:delete, delete_url)).to have_been_made.once
      end
    end

    context 'when handling the credential' do
      it 'attaches it as a Bearer header, never in the request URI', :aggregate_failures do
        stub_dissociate(status: 204)

        perform

        expect(token_exchange).to have_received(:token_for).with(current_user, nil)
        expect(a_request(:delete, delete_url).with { |req| req.uri.to_s.exclude?(token) }).to have_been_made
      end
    end
  end

  describe '#test_upstream_connection' do
    let(:test_url) { "#{repository_url}/test" }
    let(:http_method) { :post }
    let(:request_url) { test_url }
    let(:perform) { result }

    let(:test_response) do
      {
        'passed' => true,
        'http_status' => 200,
        'last_health_status' => 'healthy',
        'last_health_checked_at' => '2026-08-20T10:00:00Z'
      }
    end

    subject(:result) { client.test_upstream_connection(slug: slug, name: name) }

    def stub_ar_test(status:, body:)
      stub_request(:post, test_url).to_return(status: status, body: body, headers: json_headers)
    end

    context 'when AR returns 200 with a verdict' do
      it 'POSTs to the repository test path with the Bearer credential and no body', :aggregate_failures do
        request = stub_request(:post, test_url)
          .with(headers: { 'Authorization' => "Bearer #{token}" }) { |req| req.body.empty? }
          .to_return(status: 200, body: test_response.to_json, headers: json_headers)

        expect(result).to be_a(ArtifactRegistry::ConnectionTestResult)
        expect(request).to have_been_requested
      end

      it 'sends no Content-Type, so AR sees no body rather than an empty JSON object' do
        stub_ar_test(status: 200, body: test_response.to_json)

        result

        expect(a_request(:post, test_url).with { |req| !req.headers.key?('Content-Type') }).to have_been_made
      end

      it 'returns the parsed verdict beside the stored health fields', :aggregate_failures do
        stub_ar_test(status: 200, body: test_response.to_json)

        expect(result.passed).to be(true)
        expect(result.http_status).to eq(200)
        expect(result.last_health_status).to eq('healthy')
        expect(result.last_health_checked_at).to eq(DateTime.iso8601('2026-08-20T10:00:00Z'))
      end
    end

    context 'when the probe found the upstream unreachable' do
      let(:test_response) do
        {
          'passed' => false,
          'http_status' => nil,
          'last_health_status' => 'healthy',
          'last_health_checked_at' => '2026-08-20T10:00:00Z'
        }
      end

      it 'returns the not-passed verdict rather than raising, and keeps the stored status AR reports',
        :aggregate_failures do
        stub_ar_test(status: 200, body: test_response.to_json)

        expect(result.passed).to be(false)
        expect(result.http_status).to be_nil
        expect(result.last_health_status).to eq('healthy')
      end
    end

    context 'when AR returns 200 without a verdict' do
      it 'raises UnavailableError rather than reporting an unreachable upstream', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_ar_test(status: 200, body: test_response.except('passed').to_json)

        expect { result }.to raise_error(described_class::UnavailableError, /unexpected success response/)
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(anything, hash_including(slug: slug))
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it_behaves_like 'rejecting an unexpected success body', status: 204, body: '', body_class: 'NilClass'
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '[]', body_class: 'Array'
    end

    context 'when AR returns 404 (the route exists on remote repositories only)' do
      it 'raises ApiError rather than resolving nil, unlike the reads', :aggregate_failures do
        stub_ar_test(status: 404, body: error_envelope(code: 'not_found', request_id: 'req-test-404').to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(404)
          expect(error.code).to eq('not_found')
          expect(error.request_id).to eq('req-test-404')
        end
      end
    end

    context 'when AR returns 400 because a body reached it' do
      it 'raises ApiError carrying the envelope', :aggregate_failures do
        stub_ar_test(status: 400, body: error_envelope(code: 'bad_request', message: 'body not allowed').to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(400)
          expect(error.message).to include('body not allowed')
        end
      end
    end

    context 'when AR returns 500 (a probe ran and its verdict could not be recorded)' do
      it 'raises UnavailableError attributed to the slug', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_ar_test(status: 500, body: error_envelope(code: 'internal').to_json)

        expect { result }.to raise_error(described_class::UnavailableError) do |error|
          expect(error.status).to eq(500)
        end
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(anything, hash_including(slug: slug))
      end
    end

    context 'when the name contains a path separator' do
      let(:name) { 'evil/segment' }

      it 'percent-encodes the name segment so it cannot smuggle extra path segments', :aggregate_failures do
        encoded = stub_request(:post, "#{base_url}/api/v1/#{slug}/repositories/evil%2Fsegment/test")
          .to_return(status: 200, body: test_response.to_json, headers: json_headers)
        traversed = stub_request(:post, "#{base_url}/api/v1/#{slug}/repositories/evil/segment/test")

        result

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when slug or name is blank or a bare dot-segment' do
      where(:slug, :name) do
        ''         | 'my-repo'
        '..'       | 'my-repo'
        'my-group' | '..'
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          expect { result }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
        end
      end
    end

    context 'when a transport failure occurs on the POST' do
      before do
        stub_const('ArtifactRegistry::Transport::RETRY_OPTIONS', retry_options)
      end

      it 'does not retry the state-recording POST and issues it exactly once', :aggregate_failures do
        stub_request(:post, test_url).to_timeout

        expect { result }.to raise_error(described_class::UnavailableError)
        expect(a_request(:post, test_url)).to have_been_made.once
      end
    end
  end

  describe '#test_namespace_upstream_connection' do
    let(:connection_test_url) { "#{base_url}/api/v1/#{slug}/connection_test" }
    let(:http_method) { :post }
    let(:request_url) { connection_test_url }
    let(:perform) { result }

    let(:format) { 'maven' }
    let(:url) { 'https://upstream.example.test' }
    let(:credentials) { nil }

    let(:test_response) do
      { 'passed' => true, 'http_status' => 200 }
    end

    subject(:result) do
      client.test_namespace_upstream_connection(slug: slug, format: format, url: url, credentials: credentials)
    end

    def stub_ar_connection_test(status:, body:)
      stub_request(:post, connection_test_url).to_return(status: status, body: body, headers: json_headers)
    end

    context 'when AR returns 200 with a verdict' do
      it 'POSTs the format and url body with the Bearer credential', :aggregate_failures do
        request = stub_request(:post, connection_test_url)
          .with(headers: { 'Authorization' => "Bearer #{token}" }, body: { format: 'maven', url: url })
          .to_return(status: 200, body: test_response.to_json, headers: json_headers)

        expect(result).to be_a(ArtifactRegistry::NamespaceConnectionTestResult)
        expect(request).to have_been_requested
      end

      it 'returns the parsed verdict', :aggregate_failures do
        stub_ar_connection_test(status: 200, body: test_response.to_json)

        expect(result.passed).to be(true)
        expect(result.http_status).to eq(200)
      end
    end

    context 'with credentials' do
      let(:credentials) { { username: 'octocat', password: 's3cret' } }

      it 'forwards them in the body' do
        request = stub_request(:post, connection_test_url)
          .with(body: { format: 'maven', url: url, credentials: { username: 'octocat', password: 's3cret' } })
          .to_return(status: 200, body: test_response.to_json, headers: json_headers)

        result

        expect(request).to have_been_requested
      end
    end

    context 'without credentials' do
      it 'omits the credentials key rather than sending a null' do
        stub_ar_connection_test(status: 200, body: test_response.to_json)

        result

        expect(a_request(:post, connection_test_url).with { |req| req.body.exclude?('credentials') })
          .to have_been_made
      end
    end

    context 'when the probe found the upstream unreachable' do
      let(:test_response) { { 'passed' => false, 'http_status' => nil } }

      it 'returns the not-passed verdict rather than raising', :aggregate_failures do
        stub_ar_connection_test(status: 200, body: test_response.to_json)

        expect(result.passed).to be(false)
        expect(result.http_status).to be_nil
      end
    end

    context 'when AR returns 200 without a verdict' do
      it 'raises UnavailableError rather than reporting an unreachable upstream', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_ar_connection_test(status: 200, body: test_response.except('passed').to_json)

        expect { result }.to raise_error(described_class::UnavailableError, /unexpected success response/)
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(anything, hash_including(slug: slug))
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it_behaves_like 'rejecting an unexpected success body', status: 204, body: '', body_class: 'NilClass'
      it_behaves_like 'rejecting an unexpected success body', status: 200, body: '[]', body_class: 'Array'
    end

    context 'when AR returns 400 because the url or body was rejected' do
      it 'raises ApiError carrying the envelope', :aggregate_failures do
        stub_ar_connection_test(status: 400, body: error_envelope(code: 'bad_request', message: 'url invalid').to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(400)
          expect(error.message).to include('url invalid')
        end
      end
    end

    context 'when AR returns 404 because the slug did not resolve' do
      it 'raises ApiError rather than resolving nil, unlike the reads', :aggregate_failures do
        stub_ar_connection_test(status: 404, body: error_envelope(code: 'not_found', request_id: 'req-ct-404').to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(404)
          expect(error.code).to eq('not_found')
        end
      end
    end

    context 'when AR returns 500' do
      it 'raises UnavailableError attributed to the slug', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_ar_connection_test(status: 500, body: error_envelope(code: 'internal').to_json)

        expect { result }.to raise_error(described_class::UnavailableError) do |error|
          expect(error.status).to eq(500)
        end
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(anything, hash_including(slug: slug))
      end
    end

    context 'when the slug contains a path separator' do
      let(:slug) { 'evil/segment' }

      it 'percent-encodes the slug so it cannot smuggle extra path segments', :aggregate_failures do
        encoded = stub_request(:post, "#{base_url}/api/v1/evil%2Fsegment/connection_test")
          .to_return(status: 200, body: test_response.to_json, headers: json_headers)
        traversed = stub_request(:post, "#{base_url}/api/v1/evil/segment/connection_test")

        result

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when an argument is invalid' do
      where(:slug, :format, :url) do
        ''         | 'maven' | 'https://upstream.example.test'
        '..'       | 'maven' | 'https://upstream.example.test'
        'my-group' | 'gems'  | 'https://upstream.example.test'
        'my-group' | 'maven' | ''
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          expect { result }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
        end
      end
    end

    context 'when a transport failure occurs on the POST' do
      before do
        stub_const('ArtifactRegistry::Transport::RETRY_OPTIONS', retry_options)
      end

      it 'does not retry the POST and issues it exactly once', :aggregate_failures do
        stub_request(:post, connection_test_url).to_timeout

        expect { result }.to raise_error(described_class::UnavailableError)
        expect(a_request(:post, connection_test_url)).to have_been_made.once
      end
    end
  end

  def stub_ar_list(body:, headers: json_headers)
    stub_request(:get, request_url).to_return(status: 200, body: body, headers: headers)
  end

  def repository_permissions
    ArtifactRegistry::Permissions::Verdicts::REPOSITORY_ACTIONS.index_with(true).merge('delete_repository' => false)
  end
end
