# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanProfiles::UpdateTraversalIdsService, feature_category: :security_testing_configuration do
  let_it_be(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }
  let_it_be(:other_subgroup) { create(:group, parent: root_group) }
  let_it_be(:scan_profile) { create(:security_scan_profile, namespace: root_group) }

  let_it_be_with_reload(:project) { create(:project, namespace: root_group) }
  let_it_be_with_reload(:other_project) { create(:project, namespace: root_group) }
  let_it_be(:untouched_project) { create(:project, namespace: root_group) }

  let_it_be(:association) do
    create(:security_scan_profile_project, scan_profile: scan_profile, project: project)
  end

  let_it_be(:other_association) do
    create(:security_scan_profile_project, scan_profile: scan_profile, project: other_project)
  end

  let_it_be(:untouched_association) do
    create(:security_scan_profile_project, scan_profile: scan_profile, project: untouched_project)
  end

  describe '.execute' do
    subject(:execute) { described_class.execute(project_ids) }

    context 'when the projects have moved' do
      let(:project_ids) { [project.id, other_project.id] }

      before do
        project.update!(namespace: subgroup)
        other_project.update!(namespace: other_subgroup)
      end

      it 'writes the current traversal_ids of each project namespace' do
        execute

        expect(association.reload.traversal_ids).to eq(subgroup.traversal_ids)
        expect(other_association.reload.traversal_ids).to eq(other_subgroup.traversal_ids)
      end

      it 'bumps updated_at on the updated associations' do
        expect { execute }.to change { association.reload.updated_at }
      end

      it 'does not touch associations of other projects' do
        expect { execute }.not_to change { untouched_association.reload.traversal_ids }
      end

      it 'groups the update by traversal_ids rather than issuing one per project' do
        recorder = ActiveRecord::QueryRecorder.new { execute }

        expect(recorder.log.grep(/UPDATE "security_scan_profiles_projects"/).size).to eq(2)
      end
    end

    context 'when several projects share a namespace' do
      let(:project_ids) { [project.id, other_project.id] }

      before do
        project.update!(namespace: subgroup)
        other_project.update!(namespace: subgroup)
      end

      it 'updates them in a single statement' do
        recorder = ActiveRecord::QueryRecorder.new { execute }

        expect(recorder.log.grep(/UPDATE "security_scan_profiles_projects"/).size).to eq(1)
        expect(association.reload.traversal_ids).to eq(subgroup.traversal_ids)
        expect(other_association.reload.traversal_ids).to eq(subgroup.traversal_ids)
      end
    end

    context 'when project_ids is blank' do
      let(:project_ids) { [] }

      it 'does not query' do
        recorder = ActiveRecord::QueryRecorder.new { execute }

        expect(recorder.count).to eq(0)
      end
    end

    context 'when a project no longer exists' do
      let(:project_ids) { [non_existing_record_id] }

      it 'does nothing' do
        expect { execute }.not_to change { association.reload.traversal_ids }
      end
    end
  end
end
