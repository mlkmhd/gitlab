# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::Runners::RunnerManagerCapCronWorker, feature_category: :runner_core do
  let(:worker) { described_class.new }

  describe '#perform' do
    subject(:perform) { worker.perform }

    it_behaves_like 'an idempotent worker' do
      it 'delegates to Ci::Runners::RunnerManagerCapService and logs the result' do
        expect_next_instance_of(Ci::Runners::RunnerManagerCapService) do |service|
          expect(service).to receive(:execute)
            .and_return(ServiceResponse.success(payload: { runners_over_cap: 1, deleted_count: 2 }))
        end

        perform

        expect(worker.logging_extras).to eq({
          "extra.ci_runners_runner_manager_cap_cron_worker.status" => :success,
          "extra.ci_runners_runner_manager_cap_cron_worker.runners_over_cap" => 1,
          "extra.ci_runners_runner_manager_cap_cron_worker.deleted_count" => 2
        })
      end
    end
  end
end
