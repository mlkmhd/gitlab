# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::TriggeredWorkflow, feature_category: :vulnerability_management do
  describe 'associations' do
    it { is_expected.to belong_to(:vulnerability_occurrence).class_name('Vulnerabilities::Finding') }
    it { is_expected.to belong_to(:workflow).class_name('Ai::DuoWorkflows::Workflow') }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:vulnerability_occurrence) }
    it { is_expected.to validate_presence_of(:workflow) }
    it { is_expected.to validate_presence_of(:workflow_name) }

    describe '#vulnerability_workflow_belongs_to_same_project' do
      let_it_be(:project) { create(:project) }
      let_it_be(:other_project) { create(:project) }
      let_it_be(:vulnerability_occurrence) { create(:vulnerabilities_finding, project: project) }

      context 'when vulnerability occurrence and workflow belong to the same project' do
        let_it_be(:workflow) { create(:duo_workflows_workflow, project: project) }

        it 'is valid' do
          triggered_workflow = build(:vulnerability_triggered_workflow,
            vulnerability_occurrence: vulnerability_occurrence,
            workflow: workflow
          )

          expect(triggered_workflow).to be_valid
        end
      end

      context 'when vulnerability occurrence and workflow belong to different projects' do
        let_it_be(:workflow) { create(:duo_workflows_workflow, project: other_project) }

        it 'is invalid and adds error to workflow' do
          triggered_workflow = build(:vulnerability_triggered_workflow,
            vulnerability_occurrence: vulnerability_occurrence,
            workflow: workflow
          )

          expect(triggered_workflow).not_to be_valid

          expect(triggered_workflow.errors[:workflow])
            .to include('must belong to the same project as the vulnerability')
        end
      end

      context 'when vulnerability_occurrence is nil' do
        let_it_be(:workflow) { create(:duo_workflows_workflow, project: other_project) }

        it 'does not validate project matching' do
          triggered_workflow = build(:vulnerability_triggered_workflow,
            vulnerability_occurrence: nil,
            workflow: workflow
          )

          triggered_workflow.valid?

          expect(triggered_workflow.errors[:workflow])
            .not_to include('must belong to the same project as the vulnerability')
        end
      end

      context 'when workflow is nil' do
        it 'does not validate project matching' do
          triggered_workflow = build(:vulnerability_triggered_workflow,
            vulnerability_occurrence: vulnerability_occurrence,
            workflow: nil
          )

          triggered_workflow.valid?

          expect(triggered_workflow.errors[:workflow])
            .not_to include('must belong to the same project as the vulnerability')
        end
      end
    end
  end

  describe 'enums' do
    it 'validates enum values' do
      is_expected.to define_enum_for(:workflow_name).with_values(
        sast_fp_detection: 0,
        resolve_sast_vulnerability: 1,
        secrets_fp_detection: 2
      )
    end
  end

  describe '.with_workflow_name' do
    let_it_be(:project) { create(:project) }
    let_it_be(:finding) { create(:vulnerabilities_finding, project: project) }
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project) }

    let_it_be(:sast_fp_workflow) do
      create(:vulnerability_triggered_workflow, vulnerability_occurrence: finding, workflow: workflow,
        workflow_name: :sast_fp_detection)
    end

    let_it_be(:resolve_workflow) do
      create(:vulnerability_triggered_workflow, :resolve_sast_vulnerability, vulnerability_occurrence: finding,
        workflow: workflow)
    end

    it 'returns triggered workflows with the given name' do
      expect(described_class.with_workflow_name(:sast_fp_detection)).to contain_exactly(sast_fp_workflow)
    end
  end

  describe '.created_at_or_before and .order_by_created_at_desc' do
    let_it_be(:project) { create(:project) }
    let_it_be(:finding) { create(:vulnerabilities_finding, project: project) }
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project) }
    let_it_be(:time) { Time.current.change(usec: 0) }

    let_it_be(:older) do
      create(:vulnerability_triggered_workflow, vulnerability_occurrence: finding, workflow: workflow,
        created_at: time - 1.hour)
    end

    let_it_be(:at_time) do
      create(:vulnerability_triggered_workflow, :resolve_sast_vulnerability, vulnerability_occurrence: finding,
        workflow: workflow, created_at: time)
    end

    let_it_be(:newer) do
      create(:vulnerability_triggered_workflow, vulnerability_occurrence: finding, workflow: workflow,
        created_at: time + 1.hour)
    end

    it 'returns the rows created at or before the time, newest first' do
      expect(described_class.created_at_or_before(time).order_by_created_at_desc).to eq([at_time, older])
    end

    context 'when rows share a created_at' do
      let_it_be(:at_time_later_id) do
        create(:vulnerability_triggered_workflow, vulnerability_occurrence: finding, workflow: workflow,
          created_at: time)
      end

      it 'orders them by id, highest first' do
        expect(described_class.created_at_or_before(time).order_by_created_at_desc)
          .to eq([at_time_later_id, at_time, older])
      end
    end
  end

  describe 'callbacks' do
    describe '#assign_project_id' do
      let_it_be(:project) { create(:project) }
      let_it_be(:vulnerability_occurrence) { create(:vulnerabilities_finding, project: project) }
      let_it_be(:workflow) { create(:duo_workflows_workflow) }

      context 'when project_id is not set' do
        it 'assigns project_id from vulnerability_occurrence' do
          triggered_workflow = build(:vulnerability_triggered_workflow,
            vulnerability_occurrence: vulnerability_occurrence,
            workflow: workflow,
            project_id: nil
          )

          expect { triggered_workflow.valid? }.to change { triggered_workflow.project_id }.to(project.id)
        end
      end

      context 'when project_id is already set' do
        let_it_be(:other_project) { create(:project) }

        it 'does not override existing project_id' do
          triggered_workflow = build(:vulnerability_triggered_workflow,
            vulnerability_occurrence: vulnerability_occurrence,
            workflow: workflow,
            project_id: other_project.id
          )

          expect { triggered_workflow.valid? }.not_to change { triggered_workflow.project_id }
          expect(triggered_workflow.project_id).to eq(other_project.id)
        end
      end

      context 'when vulnerability_occurrence is nil' do
        it 'does not assign project_id' do
          triggered_workflow = build(:vulnerability_triggered_workflow,
            vulnerability_occurrence: nil,
            workflow: workflow,
            project_id: nil
          )

          expect { triggered_workflow.valid? }.not_to change { triggered_workflow.project_id }
          expect(triggered_workflow.project_id).to be_nil
        end
      end
    end
  end

  describe 'factory' do
    it 'creates a valid triggered workflow' do
      triggered_workflow = build(:vulnerability_triggered_workflow)

      expect(triggered_workflow).to be_valid
    end
  end
end
