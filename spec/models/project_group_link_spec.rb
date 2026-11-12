# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProjectGroupLink, feature_category: :groups_and_projects do
  describe "Associations" do
    it { is_expected.to belong_to(:group) }
    it { is_expected.to belong_to(:project) }
  end

  describe "Validation" do
    let(:parent_group) { create(:group) }
    let(:group) { create(:group, parent: parent_group) }
    let(:project) { create(:project, group: group) }
    let!(:project_group_link) { create(:project_group_link, project: project) }

    it { is_expected.to validate_presence_of(:project_id) }
    it { is_expected.to validate_presence_of(:group) }
    it { is_expected.to validate_presence_of(:group_access) }
    it { is_expected.to validate_inclusion_of(:group_access).in_array(Gitlab::Access.all_values) }

    it 'validates uniqueness of project_id with correct message' do
      is_expected.to validate_uniqueness_of(:project_id)
                       .scoped_to(:group_id)
                       .with_message('already shared with this group')
    end

    it "doesn't allow a project to be shared with the group it is in" do
      project_group_link.group = group

      expect(project_group_link).not_to be_valid
    end

    it "doesn't allow a project to be shared with an ancestor of the group it is in" do
      project_group_link.group = parent_group

      expect(project_group_link).not_to be_valid
    end
  end

  describe 'scopes' do
    describe '.non_guests' do
      let!(:project_group_link_reporter) { create :project_group_link, :reporter }
      let!(:project_group_link_maintainer) { create :project_group_link, :maintainer }
      let!(:project_group_link_developer) { create :project_group_link }
      let!(:project_group_link_guest) { create :project_group_link, :guest }

      it 'returns all records which are greater than Guests access' do
        expect(described_class.non_guests).to match_array([
          project_group_link_reporter,
          project_group_link_developer,
          project_group_link_maintainer
        ])
      end
    end
  end

  describe 'search by group name' do
    let_it_be(:project_group_link) { create(:project_group_link) }
    let_it_be(:group) { project_group_link.group }

    it { expect(described_class.search(group.name)).to eq([project_group_link]) }
    it { expect(described_class.search('not-a-group-name')).to be_empty }
  end

  describe '#human_access' do
    it 'delegates to Gitlab::Access' do
      project_group_link = create(:project_group_link, :reporter)
      expect(Gitlab::Access).to receive(:human_access).with(project_group_link.group_access).and_call_original

      expect(project_group_link.human_access).to eq('Reporter')
    end
  end

  describe 'database triggers on project_group_links', feature_category: :permissions do
    let_it_be(:project) { create(:project) }
    let_it_be(:other_project) { create(:project) }
    let_it_be(:group) { create(:group) }
    let_it_be(:other_group) { create(:group) }

    def refresh_events_for(project)
      Authz::ProjectAuthorizations::RefreshEvent.project.where(target_id: project.id)
    end

    def link_attributes(group)
      { project_id: project.id, group_id: group.id, group_access: Gitlab::Access::DEVELOPER }
    end

    it 'queues the project when a share is added' do
      expect { create(:project_group_link, project: project, group: group) }
        .to change { refresh_events_for(project).count }.by(1)
    end

    it 'queues the project once when shares are added in one statement' do
      expect { described_class.insert_all([link_attributes(group), link_attributes(other_group)]) }
        .to change { refresh_events_for(project).count }.by(1)
    end

    # delete and update_all skip callbacks, so only the trigger can queue these.
    it 'queues the project when a share is removed' do
      link = create(:project_group_link, project: project, group: group)

      expect { link.delete }.to change { refresh_events_for(project).count }.by(1)
    end

    it 'queues the project when the access level of a share changes' do
      link = create(:project_group_link, project: project, group: group)

      expect { described_class.where(id: link.id).update_all(group_access: Gitlab::Access::MAINTAINER) }
        .to change { refresh_events_for(project).count }.by(1)
    end

    it 'queues both projects when a share moves to another project' do
      link = create(:project_group_link, project: project, group: group)

      expect { link.update_column(:project_id, other_project.id) }
        .to change { refresh_events_for(project).count }.by(1)
        .and change { refresh_events_for(other_project).count }.by(1)
    end

    it 'queues the project when a share moves to another group' do
      link = create(:project_group_link, project: project, group: group)

      expect { link.update_column(:group_id, other_group.id) }
        .to change { refresh_events_for(project).count }.by(1)
    end

    it 'queues nothing when a column that does not affect access changes' do
      link = create(:project_group_link, project: project, group: group)

      expect { link.update!(expires_at: 1.week.from_now.to_date) }
        .not_to change { refresh_events_for(project).count }
    end
  end
end
