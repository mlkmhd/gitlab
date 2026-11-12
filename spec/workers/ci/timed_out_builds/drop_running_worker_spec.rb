# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::TimedOutBuilds::DropRunningWorker, feature_category: :continuous_integration do
  describe "#perform" do
    let(:worker) { described_class.new }

    subject(:perform) { worker.perform }

    it_behaves_like 'an idempotent worker'

    it "calls DropRunningService and logs whether the run spent its time budget", :aggregate_failures do
      expect_next_instance_of(Ci::TimedOutBuilds::DropRunningService) do |service|
        expect(service).to receive(:execute).exactly(:once).and_return(false)
      end

      expect(worker).to receive(:log_extra_metadata_on_done).with(:over_time, false)

      perform
    end
  end
end
