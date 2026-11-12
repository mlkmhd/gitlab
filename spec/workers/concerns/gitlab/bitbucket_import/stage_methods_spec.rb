# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BitbucketImport::StageMethods, feature_category: :importers do
  let(:worker_class) do
    Class.new do
      def self.name
        'TestBitbucketImportWorker'
      end

      include ApplicationWorker
      include Gitlab::BitbucketImport::StageMethods

      def import(project)
        # no-op for testing
      end
    end
  end

  let(:worker) { worker_class.new }
  let_it_be(:project) { create(:project, :import_started) }

  describe '#perform' do
    context 'when Bitbucket::Error::InvalidResponse is raised' do
      context 'with a retryable HTTP status (5xx)' do
        let(:error) { Bitbucket::Error::InvalidResponse.new('HTTP 503', http_status: 503) }

        it 'tracks the failure without failing the import and re-raises for Sidekiq retry' do
          allow(worker).to receive(:import).and_raise(error)

          expect(Gitlab::Import::ImportFailureService).to receive(:track).with(
            project_id: project.id,
            exception: error,
            error_source: worker_class.name,
            fail_import: false,
            message: 'retrying import due to transient Bitbucket API error',
            extra_attributes: { http_status_code: 503 }
          )

          expect { worker.perform(project.id) }.to raise_error(Bitbucket::Error::InvalidResponse)
        end
      end

      context 'with a retryable HTTP status (429)' do
        let(:error) { Bitbucket::Error::InvalidResponse.new('HTTP 429', http_status: 429) }

        it 'tracks the failure without failing the import and re-raises for Sidekiq retry' do
          allow(worker).to receive(:import).and_raise(error)

          expect(Gitlab::Import::ImportFailureService).to receive(:track).with(
            project_id: project.id,
            exception: error,
            error_source: worker_class.name,
            fail_import: false,
            message: 'retrying import due to transient Bitbucket API error',
            extra_attributes: { http_status_code: 429 }
          )

          expect { worker.perform(project.id) }.to raise_error(Bitbucket::Error::InvalidResponse)
        end
      end

      context 'with a retryable HTTP status (408)' do
        let(:error) { Bitbucket::Error::InvalidResponse.new('HTTP 408', http_status: 408) }

        it 'tracks the failure without failing the import and re-raises for Sidekiq retry' do
          allow(worker).to receive(:import).and_raise(error)

          expect(Gitlab::Import::ImportFailureService).to receive(:track).with(
            project_id: project.id,
            exception: error,
            error_source: worker_class.name,
            fail_import: false,
            message: 'retrying import due to transient Bitbucket API error',
            extra_attributes: { http_status_code: 408 }
          )

          expect { worker.perform(project.id) }.to raise_error(Bitbucket::Error::InvalidResponse)
        end
      end

      context 'with a fail-fast HTTP status (401)' do
        let(:error) { Bitbucket::Error::InvalidResponse.new('Unauthorized', http_status: 401) }

        it 'tracks the failure and fails the import without re-raising' do
          allow(worker).to receive(:import).and_raise(error)

          expect(Gitlab::Import::ImportFailureService).to receive(:track).with(
            project_id: project.id,
            exception: error,
            error_source: worker_class.name,
            fail_import: true,
            message: 'import failed due to invalid Bitbucket API response',
            extra_attributes: { http_status_code: 401 }
          )

          expect { worker.perform(project.id) }.not_to raise_error
        end
      end

      context 'with a fail-fast HTTP status (403)' do
        let(:error) { Bitbucket::Error::InvalidResponse.new('Forbidden', http_status: 403) }

        it 'tracks the failure and fails the import without re-raising' do
          allow(worker).to receive(:import).and_raise(error)

          expect(Gitlab::Import::ImportFailureService).to receive(:track).with(
            project_id: project.id,
            exception: error,
            error_source: worker_class.name,
            fail_import: true,
            message: 'import failed due to invalid Bitbucket API response',
            extra_attributes: { http_status_code: 403 }
          )

          expect { worker.perform(project.id) }.not_to raise_error
        end
      end

      context 'with a fail-fast HTTP status (404)' do
        let(:error) { Bitbucket::Error::InvalidResponse.new('Not Found', http_status: 404) }

        it 'tracks the failure and fails the import without re-raising' do
          allow(worker).to receive(:import).and_raise(error)

          expect(Gitlab::Import::ImportFailureService).to receive(:track).with(
            project_id: project.id,
            exception: error,
            error_source: worker_class.name,
            fail_import: true,
            message: 'import failed due to invalid Bitbucket API response',
            extra_attributes: { http_status_code: 404 }
          )

          expect { worker.perform(project.id) }.not_to raise_error
        end
      end

      context 'with no HTTP status (non-Hash body on a response that looked successful)' do
        let(:error) { Bitbucket::Error::InvalidResponse.new('Expected Hash response, got String') }

        it 're-raises for Sidekiq retry' do
          allow(worker).to receive(:import).and_raise(error)

          expect(Gitlab::Import::ImportFailureService).to receive(:track).with(
            project_id: project.id,
            exception: error,
            error_source: worker_class.name,
            fail_import: false,
            message: 'retrying import due to transient Bitbucket API error',
            extra_attributes: {}
          )

          expect { worker.perform(project.id) }.to raise_error(Bitbucket::Error::InvalidResponse)
        end
      end
    end

    context 'when OAuth2::Error is raised' do
      let(:oauth_response) do
        # rubocop:disable RSpec/VerifiedDoubles -- Faraday response used to construct OAuth2::Response
        faraday_response = double(Faraday::Response, status: 401, headers: {},
          body: '{"error": {"message": "Unauthorized"}}')
        allow(faraday_response).to receive(:on_complete)
        OAuth2::Response.new(faraday_response)
        # rubocop:enable RSpec/VerifiedDoubles
      end

      let(:error) { OAuth2::Error.new(oauth_response) }

      it 'tracks the failure and fails the import' do
        allow(worker).to receive(:import).and_raise(error)

        expect(Gitlab::Import::ImportFailureService).to receive(:track).with(
          project_id: project.id,
          exception: an_instance_of(StandardError),
          error_source: worker_class.name,
          fail_import: true,
          message: 'import failed due to a non-retryable Bitbucket API error',
          extra_attributes: { http_status_code: 401 }
        )

        expect { worker.perform(project.id) }.not_to raise_error
      end
    end
  end

  describe '#fail_fast_status?' do
    where(:status, :expected) do
      [
        [400, true], [401, true], [403, true], [404, true], [499, true],
        [408, false], [429, false], [500, false], [502, false], [503, false], [nil, false]
      ]
    end

    with_them do
      it 'applies a single rule: fail fast only on 4xx other than 408 and 429' do
        expect(worker.send(:fail_fast_status?, status)).to be expected
      end
    end
  end
end
