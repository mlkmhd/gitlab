# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::FailStuckWorkflowsWorker, feature_category: :duo_agent_platform do
  subject(:worker) { described_class.new }

  it 'defers on database health signals for the duo_workflows_workflows table' do
    expect(described_class.database_health_check_attrs).to include(
      gitlab_schema: :gitlab_main_org, tables: [:duo_workflows_workflows], delay_by: 1.minute)
  end

  describe '#perform' do
    it 'executes CleanStuckWorkflowsService' do
      expect_next_instance_of(::Ai::DuoWorkflows::CleanStuckWorkflowsService) do |instance|
        expect(instance).to receive(:execute)
      end

      worker.perform
    end
  end
end
