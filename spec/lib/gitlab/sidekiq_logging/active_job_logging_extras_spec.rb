# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::SidekiqLogging::ActiveJobLoggingExtras, feature_category: :application_instrumentation do
  let(:job_class) do
    Class.new(ActiveJob::Base) do # rubocop:disable Rails/ApplicationJob -- ActiveJob::Base is what is being extended
      include Gitlab::SidekiqLogging::ActiveJobLoggingExtras::Job
    end
  end

  let(:job) { job_class.new }
  let(:wrapper) { Class.new { include Gitlab::SidekiqLogging::ActiveJobLoggingExtras::Wrapper }.new }

  before do
    stub_const('Foo::SomeJob', job_class)
  end

  context 'with a request store', :request_store do
    it 'logs metadata under the job class prefix' do
      job.log_extra_metadata_on_done(:key1, 15)
      job.log_hash_metadata_on_done(key2: 'a', key3: 16)

      expect(job).to log_extra_metadata_on_done(key1: 15, key2: 'a', key3: 16)
    end

    it 'exposes logged metadata to the wrapper' do
      job.log_extra_metadata_on_done(:key1, 15)

      expect(wrapper.logging_extras).to eq(job.logging_extras)
      expect(wrapper.logging_extras).not_to be_empty
    end

    it 'returns an empty hash when nothing was logged' do
      expect(wrapper.logging_extras).to eq({})
    end
  end

  context 'without a request store' do
    it 'does not keep logged metadata' do
      job.log_extra_metadata_on_done(:key1, 15)

      expect(wrapper.logging_extras).to eq({})
    end
  end
end
