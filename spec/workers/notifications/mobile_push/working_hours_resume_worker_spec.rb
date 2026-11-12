# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Notifications::MobilePush::WorkingHoursResumeWorker, feature_category: :notifications do
  let(:service) { instance_double(::Notifications::MobilePush::SendWorkingHoursSummariesService) }

  subject(:worker) { described_class.new }

  before do
    allow(::Notifications::MobilePush::SendWorkingHoursSummariesService).to receive(:new).and_return(service)
    allow(service).to receive(:execute).and_return(ServiceResponse.success(payload: { delivered: 2, rescheduled: 1 }))
  end

  it_behaves_like 'an idempotent worker'

  describe '#perform' do
    it 'runs the service and logs each outcome' do
      expect(worker).to receive(:log_extra_metadata_on_done).with(:delivered, 2)
      expect(worker).to receive(:log_extra_metadata_on_done).with(:rescheduled, 1)

      worker.perform

      expect(service).to have_received(:execute)
    end

    it 'sends nothing while the instance-wide dispatch flag is off' do
      stub_feature_flags(mobile_push_notifications_dispatch: false)

      worker.perform

      expect(service).not_to have_received(:execute)
    end
  end
end
