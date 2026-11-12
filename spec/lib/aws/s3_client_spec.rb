# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Aws::S3Client, feature_category: :audit_events do
  let_it_be(:region) { 'eu-west-1' }
  let_it_be(:access_key_id) { 'AKIARANDOM123' }
  let_it_be(:secret_access_key) { 'TOPSECRET/XYZ' }

  let(:s3_client) { described_class.new(access_key_id, secret_access_key, region) }

  describe '#initialize' do
    it 'only sets the region, credentials and continue timeout by default' do
      expect(Aws::S3::Client).to receive(:new).with(
        { region: region, credentials: kind_of(Aws::Credentials), http_continue_timeout: nil }
      ).and_call_original

      s3_client
    end

    it 'passes client options through to the AWS SDK client' do
      expect(Aws::S3::Client).to receive(:new).with(
        { region: region, credentials: kind_of(Aws::Credentials), http_continue_timeout: nil,
          http_read_timeout: 8, retry_limit: 1 }
      ).and_call_original

      described_class.new(access_key_id, secret_access_key, region, http_read_timeout: 8, retry_limit: 1)
    end
  end

  describe '#upload_object' do
    let(:key) { 'file.txt' }
    let(:bucket_name) { 'gitlab-audit-logs' }
    let(:body) { 'content' }
    let(:content_type) { 'Text/plain' }

    it 'calls put_object with correct params' do
      allow_next_instance_of(Aws::S3::Client) do |s3_client|
        expect(s3_client).to receive(:put_object).with(
          {
            key: key,
            bucket: bucket_name,
            body: body,
            content_type: 'Text/plain'
          }
        )
      end

      s3_client.upload_object(key, bucket_name, body, content_type)
    end
  end
end
