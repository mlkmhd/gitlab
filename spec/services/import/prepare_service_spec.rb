# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::PrepareService, feature_category: :importers do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user) }

  let(:file) { double }
  let(:upload_service) { double }
  let(:uploader) { double }
  let(:upload) { double }

  let(:service) { described_class.new(project, user, file: file) }

  subject { service.execute }

  context 'when file is uploaded correctly' do
    let(:upload_id) { 99 }

    before do
      mock_upload
    end

    it 'raises NotImplemented error for worker' do
      expect { subject }.to raise_error(NotImplementedError)
    end

    context 'when a job is enqueued' do
      before do
        worker = double

        allow(service).to receive(:worker).and_return(worker)
        allow(worker).to receive(:perform_async)
      end

      it 'raises NotImplemented error for success_message when a job is enqueued' do
        expect { subject }.to raise_error(NotImplementedError)
      end

      it 'returns a success respnse when a success_message is implemented' do
        message = 'It works!'

        allow(service).to receive(:success_message).and_return(message)

        result = subject

        expect(result).to be_success
        expect(result.message).to eq(message)
      end
    end
  end

  context 'when file upload fails' do
    before do
      mock_upload(false)
    end

    it 'returns an error message' do
      result = subject

      expect(result[:status]).to eq(:error)
      expect(result[:message]).to eq('File upload error.')
    end
  end

  describe 'rate limiting' do
    let(:upload_id) { 99 }
    let(:worker) { class_double(WorkItems::ImportWorkItemsCsvWorker, perform_async: nil) }
    let(:service) { new_service }

    def new_service
      described_class.new(project, user, file: file).tap do |service|
        allow(service).to receive_messages(worker: worker, success_message: 'It works!')
      end
    end

    before do
      mock_upload
    end

    context 'when the user is over the rate limit' do
      before do
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(:issuable_csv_import, scope: { user: user }, users_allowlist: [])
          .and_return(true)
      end

      it 'raises a rate limit error and does not upload or enqueue the import', :aggregate_failures do
        expect(UploadService).not_to receive(:new)
        expect(worker).not_to receive(:perform_async)

        expect { subject }.to raise_error(RateLimitedService::RateLimitedError)
      end
    end

    context 'when the user reaches the limit', :freeze_time, :clean_gitlab_redis_rate_limiting do
      it 'raises a rate limit error after 20 imports in an hour', :aggregate_failures do
        20.times { new_service.execute }

        expect { new_service.execute }.to raise_error(RateLimitedService::RateLimitedError)
        expect(worker).to have_received(:perform_async).exactly(20).times
      end
    end

    context 'when the limit is changed in the application settings', :freeze_time, :clean_gitlab_redis_rate_limiting do
      before do
        stub_application_setting(issuable_csv_import_limit: 2)
      end

      it 'raises a rate limit error after the configured number of imports', :aggregate_failures do
        2.times { new_service.execute }

        expect { new_service.execute }.to raise_error(RateLimitedService::RateLimitedError)
        expect(worker).to have_received(:perform_async).twice
      end
    end

    context 'when the limit is set to 0', :freeze_time, :clean_gitlab_redis_rate_limiting do
      before do
        stub_application_setting(issuable_csv_import_limit: 0)
      end

      it 'does not rate limit the imports' do
        21.times { new_service.execute }

        expect(worker).to have_received(:perform_async).exactly(21).times
      end
    end

    context 'when issuable_csv_import_rate_limit is disabled', :freeze_time, :clean_gitlab_redis_rate_limiting do
      before do
        stub_feature_flags(issuable_csv_import_rate_limit: false)
      end

      it 'does not rate limit the imports' do
        21.times { new_service.execute }

        expect(worker).to have_received(:perform_async).exactly(21).times
      end
    end
  end
end
