# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Ai::DuoWorkflows::WorkflowTokenScope, feature_category: :duo_agent_platform do
  describe '.for' do
    it 'names the workflow' do
      expect(described_class.for(42)).to eq(['duo_workflow:42'])
    end

    it 'is empty without a workflow ID' do
      expect(described_class.for(nil)).to eq([])
    end

    it 'refuses an ID that is not an integer' do
      expect { described_class.for('1 api') }.to raise_error(ArgumentError)
    end
  end

  describe '.workflow_id_from' do
    it 'reads the workflow ID' do
      expect(described_class.workflow_id_from(%w[ai_workflows mcp duo_workflow:42])).to eq(42)
    end

    it 'is nil without a workflow scope' do
      expect(described_class.workflow_id_from(%w[ai_workflows mcp])).to be_nil
    end

    it 'is nil when two workflows are named' do
      expect(described_class.workflow_id_from(%w[duo_workflow:1 duo_workflow:2])).to be_nil
    end

    it 'ignores a scope that only starts like one' do
      expect(described_class.workflow_id_from(%w[duo_workflow:42x])).to be_nil
    end

    it 'is nil when a malformed workflow scope sits beside a valid one' do
      expect(described_class.workflow_id_from(%w[duo_workflow:42 duo_workflow:abc])).to be_nil
    end
  end

  describe '.bound?' do
    it 'is true when any scope names a workflow, even a malformed one' do
      expect(described_class.bound?(%w[mcp duo_workflow:42])).to be(true)
      expect(described_class.bound?(%w[mcp duo_workflow:abc])).to be(true)
    end

    it 'is false without a workflow scope' do
      expect(described_class.bound?(%w[ai_workflows mcp])).to be(false)
    end
  end

  describe '.allows_workflow?' do
    it 'allows any workflow for an unbound token' do
      expect(described_class.allows_workflow?(%w[ai_workflows mcp], 42)).to be(true)
    end

    it 'allows the workflow the token is bound to' do
      expect(described_class.allows_workflow?(%w[ai_workflows duo_workflow:42], 42)).to be(true)
    end

    it 'refuses another workflow' do
      expect(described_class.allows_workflow?(%w[duo_workflow:42], 43)).to be(false)
    end

    it 'refuses a bound token when no workflow is given' do
      expect(described_class.allows_workflow?(%w[duo_workflow:42], nil)).to be(false)
    end

    it 'refuses a token that names two workflows' do
      expect(described_class.allows_workflow?(%w[duo_workflow:42 duo_workflow:43], 42)).to be(false)
    end

    it 'refuses a malformed workflow scope' do
      expect(described_class.allows_workflow?(%w[duo_workflow:42x], 42)).to be(false)
    end
  end

  describe '.without' do
    it 'drops workflow scopes and keeps the rest' do
      expect(described_class.without(%w[ai_workflows duo_workflow:42 mcp duo_workflow:x])).to eq(%w[ai_workflows mcp])
    end
  end
end
