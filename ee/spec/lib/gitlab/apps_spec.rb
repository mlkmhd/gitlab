# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Apps, feature_category: :team_planning do
  describe '.for' do
    let_it_be(:root_group) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: root_group) }
    let_it_be(:project) { create(:project, group: subgroup) }

    it 'returns the apps mounted at the given mount point' do
      expect(described_class.for(project, mount: :pipeline).map(&:id)).to contain_exactly('pipeline_visualizer')
    end

    it 'returns no apps without a namespace' do
      expect(described_class.for(nil, mount: :pipeline)).to be_empty
    end

    it 'raises for an unknown mount point' do
      expect { described_class.for(project, mount: :footer) }.to raise_error(ArgumentError)
    end

    context 'when the gitlab_apps feature flag is disabled' do
      before do
        stub_feature_flags(gitlab_apps: false)
      end

      it 'returns no apps' do
        expect(described_class.for(project, mount: :pipeline)).to be_empty
      end
    end

    context 'when the gitlab_apps feature flag is enabled only for the top-level group' do
      let_it_be(:other_project) { create(:project) }

      before do
        stub_feature_flags(gitlab_apps: root_group)
      end

      it 'returns apps anywhere in that hierarchy and nowhere else', :aggregate_failures do
        expect(described_class.for(subgroup, mount: :pipeline)).not_to be_empty
        expect(described_class.for(project, mount: :pipeline)).not_to be_empty
        expect(described_class.for(other_project, mount: :pipeline)).to be_empty
      end
    end
  end

  describe Gitlab::Apps::App do
    describe '#to_nav_item' do
      it 'returns a super sidebar nav item with a namespaced id' do
        app = described_class.new(id: 'planner', title: 'GitLab Planner', icon: 'planning',
          url: 'https://planner.example.com/', mount_points: %i[pipeline])

        expect(app.to_nav_item).to eq(
          id: 'gitlab_app_planner', title: 'GitLab Planner', icon: 'planning', link: 'https://planner.example.com/'
        )
      end
    end
  end
end
