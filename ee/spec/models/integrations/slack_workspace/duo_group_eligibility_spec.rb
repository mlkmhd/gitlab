# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackWorkspace::DuoGroupEligibility, feature_category: :integrations do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:group) { create(:group, organization: organization) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:other_group) { create(:group, organization: organization) }

  let(:team_id) { 'T_ACME' }

  subject(:eligibility) { described_class.new(group, team_id) }

  def install(parent, team_id: 'T_ACME', **attrs)
    trait = parent.is_a?(::Project) ? :project : :group
    create(:slack_integration, trait, parent.class.name.underscore.to_sym => parent, team_id: team_id, **attrs)
  end

  def instance_install
    create(:slack_integration, :instance, organization: organization, team_id: team_id)
  end

  describe '#decided_by' do
    it 'is nil when the workspace is not installed in the hierarchy' do
      install(other_group)

      expect(eligibility.decided_by).to be_nil
    end

    it 'is the Owner when the workspace is installed in a subgroup or project' do
      install(project)

      expect(eligibility.decided_by).to eq(:owner)
    end

    it 'is nil for a subgroup, even with its own install' do
      install(subgroup)

      expect(described_class.new(subgroup, team_id).decided_by).to be_nil
    end

    context 'when the workspace is installed for the instance' do
      before do
        instance_install
      end

      it 'is the administrator, also for a group with its own install' do
        install(group)

        expect(eligibility.decided_by).to eq(:admin)
      end

      it 'ignores the instance install on GitLab.com' do
        stub_saas_features(gitlab_com_subscriptions: true)

        expect(eligibility.decided_by).to be_nil
      end
    end

    context 'when the group is archived or scheduled for deletion' do
      it 'is nil for an archived group, also for an instance install' do
        archived = create(:group, organization: organization)
        archived.namespace_settings.update!(archived: true)
        install(archived)
        instance_install

        expect(described_class.new(archived, team_id).decided_by).to be_nil
      end

      it 'is nil for a group scheduled for deletion' do
        scheduled = create(:group, :deletion_scheduled, organization: organization)
        install(scheduled)

        expect(described_class.new(scheduled, team_id).decided_by).to be_nil
      end
    end
  end

  describe '#eligible?' do
    it 'holds while the group is still eligible' do
      install(subgroup)

      expect(eligibility).to be_eligible
    end

    it 'fails after the last install in the hierarchy is gone' do
      installation = install(subgroup)
      installation.integration.destroy!

      expect(eligibility).not_to be_eligible
    end
  end

  describe '#inactive?' do
    it 'is true for an archived group and false otherwise' do
      archived = create(:group, organization: organization)
      archived.namespace_settings.update!(archived: true)

      expect(eligibility).not_to be_inactive
      expect(described_class.new(archived, team_id)).to be_inactive
    end
  end

  describe '#instance_install?' do
    it 'is false without an instance install, true with one, and false on GitLab.com' do
      expect(eligibility.instance_install?).to be(false)

      instance_install

      expect(described_class.new(group, team_id).instance_install?).to be(true)

      stub_saas_features(gitlab_com_subscriptions: true)

      expect(described_class.new(group, team_id).instance_install?).to be(false)
    end

    it 'takes the answer a page already loaded' do
      instance_install

      expect(described_class.new(group, team_id, instance_install: false).instance_install?).to be(false)
    end
  end

  describe 'with a preloaded install answer' do
    it 'decides from it, without reading the installs' do
      eligibility = described_class.new(group, team_id, installed_in_hierarchy: true, instance_install: false)

      expect(SlackIntegration).not_to receive(:with_bot)
      expect(eligibility.decided_by).to eq(:owner)
      expect(described_class.new(group, team_id, installed_in_hierarchy: false, instance_install: false))
        .not_to be_eligible
    end
  end

  describe '.installed_in_hierarchies' do
    it 'answers every pair in one query' do
      install(subgroup)
      install(create(:project, group: other_group), team_id: 'T_OTHER')
      pairs = [['T_ACME', group], ['T_ACME', other_group], ['T_OTHER', other_group], ['T_OTHER', group]]

      expect { described_class.installed_in_hierarchies(pairs) }.not_to exceed_query_limit(1)
      expect(described_class.installed_in_hierarchies(pairs))
        .to contain_exactly(['T_ACME', group.id], ['T_OTHER', other_group.id])
    end

    it 'is empty without pairs' do
      expect(described_class.installed_in_hierarchies([])).to be_empty
    end
  end
end
