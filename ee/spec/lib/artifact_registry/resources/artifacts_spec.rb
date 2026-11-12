# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::Resources::Artifacts, :aggregate_failures, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  include_context 'with an Artifact Registry resource'

  describe '#bulk_delete_artifacts' do
    let(:format) { 'maven' }
    let(:collection) { 'packages' }
    let(:bulk_delete_url) { "#{repository_url}/#{format}/#{collection}/bulk_delete" }

    subject(:result) { client.bulk_delete_artifacts(slug: slug, repository_name: name, format: format) }

    def stub_bulk_delete(status:, body: '')
      stub_request(:post, bulk_delete_url).to_return(status: status, body: body, headers: json_headers)
    end

    context 'when AR accepts the batch' do
      where(:format, :collection) do
        'maven'  | 'packages'
        'npm'    | 'packages'
        'docker' | 'images'
        'oci'    | 'images'
      end

      with_them do
        # The body is pinned as a literal: the contract closes additionalProperties on the
        # whole-collection selector, so a stray key is a 400 rather than a wider delete.
        it 'posts the whole-collection selector to the route the format selects, and returns nil',
          :aggregate_failures do
          request = stub_request(:post, bulk_delete_url)
            .with(body: '{"delete_all":true}', headers: { 'Authorization' => "Bearer #{token}" })
            .to_return(status: 202, body: '', headers: json_headers)

          expect(result).to be_nil
          expect(request).to have_been_requested
        end
      end
    end

    context 'when the job backend cannot take the enqueue (503)' do
      # Each collection declares its own 503 in the contract, so both are asserted rather than one standing in for the
      # other. The name stops at what a 503 reports, because the same UnavailableError also covers a lost response,
      # where re-sending the selector is not the recovery: the caller has to re-read instead.
      where(:format, :collection) do
        'maven'  | 'packages'
        'docker' | 'images'
      end

      with_them do
        it 'raises UnavailableError, the enqueue refused and nothing applied' do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_bulk_delete(status: 503, body: error_envelope(code: 'service_unavailable').to_json)

          expect { result }.to raise_error(described_class::UnavailableError)
        end
      end
    end

    context 'when AR returns a mapped 4xx' do
      # 404 is the virtual-repository answer, since a virtual repository owns no artifact rows to act on; 400 is what
      # the closed selector schema answers for a stray body key. Neither may become an absence: this method takes no
      # nil_on_missing wrapper, and adding one would turn a whole-collection delete that never happened into a success.
      where(:status) { [400, 404] }

      with_them do
        it 'raises ApiError carrying the status rather than returning nil', :aggregate_failures do
          stub_bulk_delete(status: status, body: error_envelope(request_id: 'req-bulk-id').to_json)

          expect { result }.to raise_error(described_class::ApiError) do |error|
            expect(error.status).to eq(status)
            expect(error.request_id).to eq('req-bulk-id')
          end
        end
      end
    end

    context 'when AR refuses the write (401 and 403)' do
      # AuthorizationError descends from Error and not from ApiError, so a caller rescuing ApiError
      # to report a failed delete does not catch it; both halves are pinned here because the
      # mutations built on this method depend on them.
      where(:status) { [401, 403] }

      with_them do
        it 'raises AuthorizationError, not ApiError, and reports the auth failure once', :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_bulk_delete(status: status, body: error_envelope(code: 'forbidden').to_json)

          expect { result }.to raise_error(described_class::AuthorizationError) do |error|
            expect(error.status).to eq(status)
            expect(error).not_to be_a(described_class::ApiError)
          end
          expect_auth_failure_reported_once(status)
        end
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it 'raises UnavailableError rather than reading another 2xx as acceptance' do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_bulk_delete(status: 200, body: '{}')

        expect { result }.to raise_error(described_class::UnavailableError, /unexpected success response/)
      end
    end

    context 'when the format is in neither the package nor the image list' do
      let(:format) { 'conda' }

      it 'raises ArgumentError naming every served format, before any request', :aggregate_failures do
        expect { result }.to raise_error(ArgumentError, 'format must be one of: maven, npm, docker, oci')
        expect(token_exchange).not_to have_received(:token_for)
        expect(a_request(:any, %r{\A#{Regexp.escape(base_url)}})).not_to have_been_made
      end
    end

    context 'when slug or the repository name is blank or a bare dot-segment' do
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

    context 'when the slug and the repository name contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }

      it 'percent-encodes each path segment so a value cannot smuggle extra path segments',
        :aggregate_failures do
        encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/#{collection}/bulk_delete"
        encoded = stub_request(:post, "#{base_url}/api/v1/#{encoded_path}")
          .to_return(status: 202, body: '', headers: json_headers)
        traversed = stub_request(:post,
          "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/#{collection}/bulk_delete")

        result

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when handling the credential' do
      it 'attaches it as a Bearer header, never in the request URI or the body', :aggregate_failures do
        stub_bulk_delete(status: 202)

        result

        expect(token_exchange).to have_received(:token_for).with(current_user, nil)
        expect(
          a_request(:post, bulk_delete_url)
            .with { |req| req.uri.to_s.exclude?(token) && req.body.to_s.exclude?(token) }
        ).to have_been_made
      end

      it 'redacts a credential AR echoes in an error envelope, in both the raised and the logged error',
        :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        echoed = "rejected: Authorization: Bearer #{jwt_credential}"
        stub_bulk_delete(status: 503, body: error_envelope(message: echoed).to_json)

        expect { result }.to raise_error(described_class::UnavailableError) do |error|
          expect(error.message).to include('Bearer [REDACTED]')
          expect(error.message).not_to include(jwt_credential)
        end
        expect(Gitlab::ErrorTracking).to have_received(:log_exception) do |logged, _context|
          expect(logged.message).not_to include(jwt_credential)
        end
      end
    end

    context 'when a transport failure occurs on the POST' do
      before do
        stub_const('ArtifactRegistry::Transport::RETRY_OPTIONS', retry_options)
      end

      it 'does not retry the eviction and issues the POST exactly once', :aggregate_failures do
        stub_request(:post, bulk_delete_url).to_timeout

        expect { result }.to raise_error(described_class::UnavailableError)
        expect(a_request(:post, bulk_delete_url)).to have_been_made.once
      end
    end
  end

  describe '#delete_artifact' do
    let(:format) { 'maven' }
    let(:collection) { 'packages' }
    let(:artifact_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
    let(:delete_url) { "#{repository_url}/#{format}/#{collection}/#{artifact_id}" }

    subject(:result) do
      client.delete_artifact(slug: slug, repository_name: name, format: format, id: artifact_id)
    end

    def stub_artifact_delete(status:, body: '')
      stub_request(:delete, delete_url).to_return(status: status, body: body, headers: json_headers)
    end

    context 'when AR accepts the delete' do
      where(:format, :collection) do
        'maven'  | 'packages'
        'npm'    | 'packages'
        'docker' | 'images'
        'oci'    | 'images'
      end

      with_them do
        it 'issues the delete for the id under the route the format selects, and returns nil',
          :aggregate_failures do
          request = stub_request(:delete, delete_url)
            .with(headers: { 'Authorization' => "Bearer #{token}" })
            .to_return(status: 202, body: '', headers: json_headers)

          expect(result).to be_nil
          expect(request).to have_been_requested
        end
      end
    end

    context 'when the artifact is already gone (404)' do
      # Unlike delete_repository, this takes no idempotence rescue: AR distinguishes a missing
      # artifact from an accepted delete, so the caller is told rather than shown a success.
      it 'raises ApiError carrying the status rather than resolving nil', :aggregate_failures do
        stub_artifact_delete(status: 404, body: error_envelope(code: 'not_found').to_json)

        expect { result }.to raise_error(described_class::ApiError) do |error|
          expect(error.status).to eq(404)
          expect(error.code).to eq('not_found')
        end
      end
    end

    context 'when AR refuses the write (401 and 403)' do
      where(:status) { [401, 403] }

      with_them do
        it 'raises AuthorizationError, not ApiError, and reports the auth failure once', :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          stub_artifact_delete(status: status, body: error_envelope(code: 'forbidden').to_json)

          expect { result }.to raise_error(described_class::AuthorizationError) do |error|
            expect(error.status).to eq(status)
            expect(error).not_to be_a(described_class::ApiError)
          end
          expect_auth_failure_reported_once(status)
        end
      end
    end

    context 'when AR fails the delete (500)' do
      # The contract declares 500 on this route, and 500 is the one delete_artifact status that
      # reaches the logging path, so the logged half of the redaction is exercised here rather than
      # left to the bulk method.
      it 'raises UnavailableError and redacts an echoed credential in both errors', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        echoed = "rejected: Authorization: Bearer #{jwt_credential}"
        stub_artifact_delete(status: 500, body: error_envelope(message: echoed).to_json)

        expect { result }.to raise_error(described_class::UnavailableError) do |error|
          expect(error.message).to include('Bearer [REDACTED]')
          expect(error.message).not_to include(jwt_credential)
        end
        expect(Gitlab::ErrorTracking).to have_received(:log_exception) do |logged, _context|
          expect(logged.message).not_to include(jwt_credential)
        end
      end
    end

    context 'when AR returns a success response the contract does not allow' do
      it 'raises UnavailableError rather than reading another 2xx as acceptance' do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_artifact_delete(status: 200, body: '{}')

        expect { result }.to raise_error(described_class::UnavailableError, /unexpected success response/)
      end
    end

    context 'when the format is in neither the package nor the image list' do
      let(:format) { 'conda' }

      it 'raises ArgumentError naming every served format, before any request', :aggregate_failures do
        expect { result }.to raise_error(ArgumentError, 'format must be one of: maven, npm, docker, oci')
        expect(token_exchange).not_to have_received(:token_for)
        expect(a_request(:any, %r{\A#{Regexp.escape(base_url)}})).not_to have_been_made
      end
    end

    context 'when slug, the repository name, or the id is blank or a bare dot-segment' do
      where(:slug, :name, :artifact_id) do
        ''         | 'my-repo' | 'a1b2c3d4-0000-0000-0000-000000000000'
        '..'       | 'my-repo' | 'a1b2c3d4-0000-0000-0000-000000000000'
        'my-group' | '..'      | 'a1b2c3d4-0000-0000-0000-000000000000'
        'my-group' | 'my-repo' | nil
        'my-group' | 'my-repo' | '..'
      end

      with_them do
        it 'raises ArgumentError without contacting the token exchange or AR', :aggregate_failures do
          expect { result }.to raise_error(ArgumentError)
          expect(token_exchange).not_to have_received(:token_for)
        end
      end

      context 'when the id is blank' do
        let(:artifact_id) { '' }

        it 'sends nothing at the collection route, which a blank id would otherwise address' do
          request = stub_request(:delete, "#{repository_url}/#{format}/#{collection}/")

          expect { result }.to raise_error(ArgumentError)
          expect(request).not_to have_been_requested
        end
      end
    end

    context 'when the slug, the repository name, and the id contain path separators' do
      let(:slug) { 'grp/x' }
      let(:name) { 'evil/segment' }
      let(:artifact_id) { 'a/b' }

      it 'percent-encodes each path segment so a value cannot smuggle extra path segments',
        :aggregate_failures do
        encoded_path = "grp%2Fx/repositories/evil%2Fsegment/#{format}/#{collection}/a%2Fb"
        encoded = stub_request(:delete, "#{base_url}/api/v1/#{encoded_path}")
          .to_return(status: 202, body: '', headers: json_headers)
        traversed = stub_request(:delete,
          "#{base_url}/api/v1/grp/x/repositories/evil/segment/#{format}/#{collection}/a/b")

        result

        expect(encoded).to have_been_requested
        expect(traversed).not_to have_been_requested
      end
    end

    context 'when handling the credential' do
      it 'attaches it as a Bearer header, never in the request URI', :aggregate_failures do
        stub_artifact_delete(status: 202)

        result

        expect(token_exchange).to have_received(:token_for).with(current_user, nil)
        expect(a_request(:delete, delete_url).with { |req| req.uri.to_s.exclude?(token) }).to have_been_made
      end
    end

    context 'when a transport failure occurs on the DELETE' do
      before do
        stub_const('ArtifactRegistry::Transport::RETRY_OPTIONS', retry_options)
      end

      # The point of narrowing RETRY_OPTIONS[:methods]: a replayed eviction hits an artifact the
      # first attempt already removed, and AR's 404 would report a failure for a delete that worked.
      it 'does not retry the eviction and issues the DELETE exactly once', :aggregate_failures do
        stub_request(:delete, delete_url).to_timeout

        expect { result }.to raise_error(described_class::UnavailableError)
        expect(a_request(:delete, delete_url)).to have_been_made.once
      end
    end
  end
end
