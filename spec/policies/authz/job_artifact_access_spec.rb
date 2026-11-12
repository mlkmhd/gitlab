# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::JobArtifactAccess, feature_category: :permissions do
  let_it_be(:project) { create(:project) }

  let(:access) do
    described_class.new(project: project, accessibility: 'private', file_type: 'junit', duo_workflow: false)
  end

  describe '.for' do
    it 'reads the access attributes, taking the project and pipeline source from the job' do
      pipeline = build(:ci_pipeline, project: project, source: :duo_workflow)
      artifact = build(:ci_job_artifact, :junit, :private, job: build(:ci_build, pipeline: pipeline))

      expect(described_class.for(artifact))
        .to eq(described_class.new(project: project, accessibility: 'private', file_type: 'junit', duo_workflow: true))
    end
  end

  # Authz::JobArtifactAccessPolicy may only read these
  it 'has a fixed set of attributes' do
    expect(described_class.members).to eq(%i[project accessibility file_type duo_workflow])
  end

  describe '#initialize' do
    it 'normalizes symbols so the policy cannot miss a value' do
      access = described_class.new(project: project, accessibility: :none, file_type: :junit, duo_workflow: false)

      expect(access).to have_attributes(accessibility: 'none', file_type: 'junit')
    end
  end

  describe '#id' do
    it 'is built from every attribute' do
      expect(access.id).to eq("#{project.id}:private:junit:false")
    end
  end
end
