# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Milestone, :elastic, feature_category: :global_search do
  before do
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
  end

  it_behaves_like 'limited indexing is enabled' do
    let_it_be(:object) { create :milestone, project: project }
  end

  describe 'searching', :sidekiq_inline do
    let_it_be(:user) { create(:user) }
    let_it_be(:project) { create(:project, developers: user) }
    let_it_be(:milestone_1) { create(:milestone, title: 'bla-bla term1', project: project) }
    let_it_be(:milestone_2) { create(:milestone, title: 'bla-bla term2', project: project) }
    let_it_be(:milestone_3) { create(:milestone, project: project) }
    # The milestone you have no access to except as an administrator
    let_it_be(:milestone_4) { create(:milestone, title: 'bla-bla term3') }

    before do
      Elastic::ProcessInitialBookkeepingService.track!(milestone_1, milestone_2, milestone_3, milestone_4)
      ensure_elasticsearch_index!
    end

    it 'searches milestones', :enable_admin_mode do
      options = { search_level: 'global', project_ids: [project.id], current_user: user }

      expect(described_class.elastic_search('(term1 | term2 | term3) +bla-bla', options: options).total_count).to eq(2)

      options = { current_user: create(:admin), search_level: 'global', project_ids: :any }
      expect(described_class.elastic_search('bla-bla', options: options).total_count).to eq(3)
    end

    context 'with group milestones' do
      let_it_be(:non_member) { create(:user) }
      let_it_be(:group_member) { create(:user) }
      let_it_be(:project_member) { create(:user) }
      let_it_be(:admin) { create(:admin) }
      let_it_be(:public_group) { create(:group, :public) }
      let_it_be(:private_group) { create(:group, :private, guests: group_member) }
      let_it_be(:private_group_project) { create(:project, :private, group: private_group, guests: project_member) }
      let_it_be(:restricted_public_project) do
        create(:project, :public, issues_access_level: ProjectFeature::PRIVATE,
          merge_requests_access_level: ProjectFeature::PRIVATE)
      end

      let_it_be(:public_group_milestone) { create(:milestone, title: 'grouped term5', group: public_group) }
      let_it_be(:private_group_milestone) { create(:milestone, title: 'grouped term6', group: private_group) }
      let_it_be(:restricted_project_milestone) do
        create(:milestone, title: 'grouped term7', project: restricted_public_project)
      end

      before do
        Elastic::ProcessInitialBookkeepingService.track!(
          public_group_milestone, private_group_milestone, restricted_project_milestone
        )
        ensure_elasticsearch_index!
      end

      def search_ids(current_user)
        options = { search_level: 'global', current_user: current_user, public_and_internal_projects: true }

        described_class.elastic_search('grouped', options: options).records.map(&:id)
      end

      it 'routes group milestones by their root ancestor' do
        hits = es_client.search(
          index: Elastic::Latest::Config.index_name,
          body: { query: { bool: { filter: [{ term: { type: 'milestone' } },
            { term: { id: private_group_milestone.id } }] } } }
        ).dig('hits', 'hits')

        expect(hits.pluck('_routing')).to eq(["n_#{private_group.id}"])
      end

      it 'returns public group milestones only to a non-member' do
        expect(search_ids(non_member)).to contain_exactly(public_group_milestone.id)
      end

      it 'returns public group milestones only to an anonymous user' do
        expect(search_ids(nil)).to contain_exactly(public_group_milestone.id)
      end

      it 'returns private group milestones to a group member' do
        expect(search_ids(group_member)).to contain_exactly(public_group_milestone.id, private_group_milestone.id)
      end

      it 'returns private group milestones to a member of a project in the group' do
        expect(search_ids(project_member)).to contain_exactly(public_group_milestone.id, private_group_milestone.id)
      end

      it 'returns every group milestone to an admin', :enable_admin_mode do
        expect(search_ids(admin)).to include(public_group_milestone.id, private_group_milestone.id)
      end

      context 'when searching a group' do
        let_it_be(:parent_group) { create(:group, :public) }
        let_it_be(:searched_group) { create(:group, :public, parent: parent_group) }
        let_it_be(:subgroup) { create(:group, :public, parent: searched_group) }
        let_it_be(:subgroup_project) { create(:project, :public, group: subgroup) }
        let_it_be(:parent_milestone) { create(:milestone, title: 'scoped term8', group: parent_group) }
        let_it_be(:searched_group_milestone) { create(:milestone, title: 'scoped term9', group: searched_group) }
        let_it_be(:subgroup_milestone) { create(:milestone, title: 'scoped term10', group: subgroup) }
        let_it_be(:subgroup_project_milestone) do
          create(:milestone, title: 'scoped term11', project: subgroup_project)
        end

        before do
          Elastic::ProcessInitialBookkeepingService.track!(
            parent_milestone, searched_group_milestone, subgroup_milestone, subgroup_project_milestone
          )
          ensure_elasticsearch_index!
        end

        it 'returns milestones of the group, its ancestors and its subgroups' do
          options = { search_level: 'group', group_ids: [searched_group.id], current_user: non_member }

          ids = described_class.elastic_search('scoped', options: options).records.map(&:id)

          expect(ids).to contain_exactly(parent_milestone.id, searched_group_milestone.id, subgroup_milestone.id,
            subgroup_project_milestone.id)
        end
      end

      context 'when the ancestor group is private' do
        let_it_be(:subgroup_member) { create(:user) }
        let_it_be(:private_parent) { create(:group, :private) }
        let_it_be(:private_child) { create(:group, :private, parent: private_parent, guests: subgroup_member) }
        let_it_be(:private_parent_milestone) { create(:milestone, title: 'hidden term12', group: private_parent) }
        let_it_be(:private_child_milestone) { create(:milestone, title: 'hidden term13', group: private_child) }

        before do
          Elastic::ProcessInitialBookkeepingService.track!(private_parent_milestone, private_child_milestone)
          ensure_elasticsearch_index!
        end

        it 'does not return its milestones to a member of the subgroup only' do
          options = { search_level: 'group', group_ids: [private_child.id], current_user: subgroup_member }

          ids = described_class.elastic_search('hidden', options: options).records.map(&:id)

          expect(ids).to contain_exactly(private_child_milestone.id)
        end

        context 'when the user is a member of the ancestor group' do
          let_it_be(:parent_member) { create(:user) }
          let_it_be(:child_project) { create(:project, :private, group: private_child) }

          before_all do
            private_parent.add_guest(parent_member)
          end

          it 'returns its milestones when searching the subgroup or a project in it' do
            [
              { search_level: 'group', group_ids: [private_child.id] },
              { search_level: 'project', project_ids: [child_project.id] }
            ].each do |level_options|
              ids = described_class.elastic_search('hidden',
                options: level_options.merge(current_user: parent_member)).records.map(&:id)

              expect(ids).to include(private_parent_milestone.id)
            end
          end
        end

        context 'when the subgroup the user is a member of has a project' do
          let_it_be(:child_project_member) { create(:user) }
          let_it_be(:child_project) { create(:project, :private, group: private_child) }

          before_all do
            private_child.add_guest(child_project_member)
          end

          it 'returns its milestones at every search level, as the project grants the ancestor' do
            [
              { search_level: 'global' },
              { search_level: 'group', group_ids: [private_parent.id] },
              { search_level: 'group', group_ids: [private_child.id] },
              { search_level: 'project', project_ids: [child_project.id] }
            ].each do |level_options|
              ids = described_class.elastic_search('hidden',
                options: level_options.merge(current_user: child_project_member)).records.map(&:id)

              expect(ids).to include(private_parent_milestone.id)
            end
          end

          context 'when advanced_search_project_ancestors_via_groups is disabled' do
            before do
              stub_feature_flags(advanced_search_project_ancestors_via_groups: false)
            end

            it 'does not return its milestones' do
              ids = described_class.elastic_search('hidden',
                options: { search_level: 'global', current_user: child_project_member }).records.map(&:id)

              expect(ids).not_to include(private_parent_milestone.id)
            end
          end
        end
      end

      context 'when searching a project' do
        let_it_be(:top_group) { create(:group, :private) }
        let_it_be(:project_group) { create(:group, :private, parent: top_group) }
        let_it_be(:project_subgroup) { create(:group, :private, parent: project_group) }
        let_it_be(:sibling_group) { create(:group, :private, parent: top_group) }
        let_it_be(:searched_project) { create(:project, :private, group: project_group, guests: project_member) }
        let_it_be(:milestones) do
          [top_group, project_group, project_subgroup, sibling_group].index_with do |group|
            create(:milestone, title: "levels term14 #{group.name}", group: group)
          end.merge(searched_project => create(:milestone, title: 'levels term14 project', project: searched_project))
        end

        before do
          Elastic::ProcessInitialBookkeepingService.track!(*milestones.values)
          ensure_elasticsearch_index!
        end

        it "returns milestones of the project, its group and the group's ancestors to a project member" do
          options = { search_level: 'project', project_ids: [searched_project.id], current_user: project_member }

          ids = described_class.elastic_search('levels', options: options).records.map(&:id)

          expect(ids).to match_array(milestones.values_at(searched_project, project_group, top_group).map(&:id))
        end
      end

      context 'when advanced_search_group_milestones is disabled' do
        before do
          stub_feature_flags(advanced_search_group_milestones: false)
        end

        it 'does not return group milestones', :enable_admin_mode do
          expect(search_ids(admin)).to contain_exactly(restricted_project_milestone.id)
        end
      end
    end
  end

  describe 'group visibility change', :sidekiq_inline do
    let(:group) { create(:group, :public) }
    let(:milestone) { create(:milestone, group: group) }

    def indexed_visibility_level
      es_client.search(
        index: Elastic::Latest::Config.index_name,
        body: { query: { bool: { filter: [{ term: { type: 'milestone' } }, { term: { id: milestone.id } }] } } }
      ).dig('hits', 'hits', 0, '_source', 'visibility_level')
    end

    it 'updates the visibility_level of the indexed group milestone' do
      allow(ElasticWikiIndexerWorker).to receive(:perform_async)
      milestone
      ensure_elasticsearch_index!
      expect(indexed_visibility_level).to eq(Gitlab::VisibilityLevel::PUBLIC)

      group.update!(visibility_level: Gitlab::VisibilityLevel::PRIVATE)
      ensure_elasticsearch_index!

      expect(indexed_visibility_level).to eq(Gitlab::VisibilityLevel::PRIVATE)
    end
  end

  describe '#es_parent' do
    let_it_be(:root_group) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: root_group) }
    let_it_be(:project) { create(:project, group: subgroup) }

    it 'routes a project milestone by its project' do
      milestone = build_stubbed(:milestone, project: project)

      expect(milestone.es_parent).to eq("project_#{project.id}")
    end

    it 'routes a group milestone by its root ancestor' do
      milestone = build_stubbed(:milestone, group: subgroup)

      expect(milestone.es_parent).to eq("n_#{root_group.id}")
    end
  end

  describe 'as_indexed_json' do
    context 'for project milestone' do
      let_it_be(:milestone) { create(:milestone, :on_project) }

      let(:expected_hash) do
        milestone.attributes.extract!(
          'id',
          'iid',
          'title',
          'description',
          'project_id',
          'created_at',
          'updated_at'
        ).merge({
          'type' => milestone.es_type,
          'issues_access_level' => milestone.project.issues_access_level,
          'merge_requests_access_level' => milestone.project.merge_requests_access_level,
          'visibility_level' => milestone.project.visibility_level,
          'archived' => milestone.project.archived,
          'schema_version' => Elastic::Latest::MilestoneInstanceProxy::SCHEMA_VERSION,
          'traversal_ids' => milestone.project.elastic_namespace_ancestry,
          'organization_id' => milestone.project.organization_id,
          'organization_traversal_ids' =>
            "#{milestone.project.organization_id}/#{milestone.project.elastic_namespace_ancestry}"
        })
      end

      it 'returns json with all needed elements' do
        expect(milestone.__elasticsearch__.as_indexed_json).to eq(expected_hash)
      end
    end

    context 'for group milestone' do
      let_it_be(:milestone) { create(:milestone, :on_group) }

      let(:expected_hash) do
        milestone.attributes.extract!(
          'id',
          'iid',
          'title',
          'description',
          'project_id',
          'created_at',
          'updated_at'
        ).merge({
          'type' => milestone.es_type,
          'namespace_id' => milestone.group.id,
          'visibility_level' => milestone.group.visibility_level,
          'archived' => false,
          'schema_version' => Elastic::Latest::MilestoneInstanceProxy::SCHEMA_VERSION,
          'traversal_ids' => milestone.group.elastic_namespace_ancestry,
          'organization_id' => milestone.group.organization_id,
          'organization_traversal_ids' =>
            "#{milestone.group.organization_id}/#{milestone.group.elastic_namespace_ancestry}"
        })
      end

      it 'returns json with all needed elements' do
        expect(milestone.__elasticsearch__.as_indexed_json).to eq(expected_hash)
      end
    end

    context 'for group milestone under an archived group' do
      let_it_be(:archived_group) { create(:group, :archived) }
      let_it_be(:milestone) { create(:milestone, group: create(:group, parent: archived_group)) }

      it 'marks the document as archived' do
        expect(milestone.__elasticsearch__.as_indexed_json['archived']).to be(true)
      end
    end

    context 'for group milestones in subgroups' do
      let_it_be(:root_group) { create(:group) }

      before_all do
        create(:milestone, group: create(:group, parent: root_group))
      end

      def build_documents
        described_class.preload_for_indexing.find_each { |milestone| milestone.__elasticsearch__.as_indexed_json }
      end

      it 'does not issue a query per milestone' do
        control = ActiveRecord::QueryRecorder.new(skip_cached: false) { build_documents }

        create(:milestone, group: create(:group, parent: root_group))

        expect { build_documents }.to issue_same_number_of_queries_as(control)
      end
    end
  end

  it_behaves_like 'no results when the user cannot read cross project' do
    let(:record1) { create(:milestone, project: project, title: 'test-milestone') }
    let(:record2) { create(:milestone, project: project2, title: 'test-milestone') }
  end
end
