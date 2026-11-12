# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::Archival::Restoration::Tasks::AdjustTraversalIdsAndArchivedAttributes, feature_category: :vulnerability_management do
  describe '.execute' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }

    let(:finding) { create(:vulnerabilities_finding, :skip_false_positive_detection, project: project) }
    let(:vulnerability) { finding.vulnerability }
    let(:vulnerability_read) { vulnerability.vulnerability_read }
    let(:backup) do
      Vulnerabilities::Backups::Vulnerability.new(
        project_id: project.id,
        original_record_identifier: vulnerability.id
      )
    end

    subject(:execute) { described_class.execute(vulnerability_backups) }

    context 'when there are no backups' do
      let(:vulnerability_backups) { [] }

      it 'does not run an update' do
        expect(SecApplicationRecord.connection).not_to receive(:execute)

        execute
      end
    end

    context 'when the backups point at vulnerability reads with stale attributes' do
      let(:vulnerability_backups) { [backup] }

      before do
        vulnerability_read.update_columns(traversal_ids: [non_existing_record_id], archived: true)
      end

      it 'sets the traversal_ids and archived values of the owner project' do
        expect { execute }.to change { vulnerability_read.reload.traversal_ids }
                                .from([non_existing_record_id]).to(project.namespace.traversal_ids)
                          .and change { vulnerability_read.reload.archived }.from(true).to(false)
      end
    end
  end
end
