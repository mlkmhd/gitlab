# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/FactoryBot/AvoidCreate -- the presenter reads installs and claims from the database
RSpec.describe Integrations::SlackWorkspace::DuoWorkspacesPresenter, feature_category: :integrations do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:group) { create(:group, :private, organization: organization) }
  let_it_be(:subgroup) { create(:group, :private, parent: group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:owner) { create(:user, owner_of: group) }
  let_it_be(:maintainer) { create(:user, maintainer_of: group) }
  let_it_be(:admin) { create(:admin) }

  let(:current_user) { owner }
  let(:own_team_id) { nil }
  let(:only_team_id) { nil }
  let(:offset) { 0 }

  subject(:presenter) do
    described_class.new(group: group, current_user: current_user, own_team_id: own_team_id,
      only_team_id: only_team_id, offset: offset)
  end

  def install(parent, team_id, scopes: [])
    trait = parent.is_a?(::Project) ? :project : :group
    create(:slack_integration, trait, parent.class.name.underscore.to_sym => parent, team_id: team_id,
      team_name: "Workspace #{team_id}").tap do |installation|
      installation.update!(authorized_scope_names: scopes) if scopes.any?
    end
  end

  # What propagation creates below a group install: a copy that inherits from it.
  def inherited_copy(parent, from)
    install(parent, from.team_id).tap do |copy|
      copy.integration.update!(inherit_from_id: from.integration_id)
    end
  end

  def instance_install(team_id)
    create(:slack_integration, :instance, organization: organization, team_id: team_id, team_name: 'Instance')
  end

  describe '#rows' do
    before do
      install(subgroup, 'T_SUB')
      install(project, 'T_PROJECT')
    end

    it 'lists every workspace installed in the hierarchy, with a toggle for the Owner' do
      expect(presenter.rows).to contain_exactly(
        a_hash_including(team_id: 'T_PROJECT', state: :off, can_manage: true),
        a_hash_including(team_id: 'T_SUB', state: :off, can_manage: true)
      )
    end

    context 'for a Maintainer' do
      let(:current_user) { maintainer }

      it 'has no toggle' do
        expect(presenter.rows.pluck(:can_manage)).to all(be(false))
      end
    end

    context 'without a current user' do
      let(:current_user) { nil }

      it 'has no toggle' do
        expect(presenter.rows.pluck(:can_manage)).to all(be(false))
      end
    end

    context 'on GitLab.com, where no workspace is managed for the instance' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'has no instance-managed row' do
        expect(presenter.rows.pluck(:state)).to all(eq(:off))
      end
    end

    context "with the page's own workspace" do
      let(:own_team_id) { 'T_SUB' }

      it 'puts it first and returns it as the own row' do
        expect(presenter.rows.first).to include(team_id: 'T_SUB')
        expect(presenter.own_row).to include(team_id: 'T_SUB')
      end
    end

    context 'with a workspace installed for the instance' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        instance_install('T_INSTANCE')
        install(create(:group, :private, parent: group), 'T_INSTANCE')
      end

      it 'is no row on the group page' do
        expect(presenter.rows.pluck(:team_id)).to contain_exactly('T_SUB', 'T_PROJECT')
      end

      context "when it's the page's own connection" do
        let(:own_team_id) { 'T_INSTANCE' }

        it 'is the own row, decided by the administrator' do
          expect(presenter.own_row).to include(state: :instance_managed, can_manage: false)
          expect(presenter.rows.pluck(:team_id)).to eq(%w[T_INSTANCE T_PROJECT T_SUB])
        end
      end
    end

    context 'with a workspace the page is not connected to' do
      let(:own_team_id) { 'T_ELSEWHERE' }

      it 'has no own row' do
        expect(presenter.own_row).to be_nil
      end
    end

    context 'when GitLab Duo runs for a workspace' do
      let_it_be(:other_group) { create(:group, :private) }

      it 'is on here when the claim is the group' do
        create(:slack_workspace, team_id: 'T_SUB', duo_namespace: group)

        expect(presenter.rows).to include(a_hash_including(team_id: 'T_SUB', state: :on_here,
          duo_group: a_hash_including(id: group.id, link_kind: :settings)))
        expect(presenter.runs_here?).to be(true)
      end

      it 'names another group only to someone who can see it' do
        install(other_group, 'T_SUB')
        create(:slack_workspace, team_id: 'T_SUB', duo_namespace: other_group)

        expect(presenter.rows).to include(a_hash_including(team_id: 'T_SUB', state: :elsewhere, duo_group: nil))
        expect(presenter.runs_here?).to be(false)
      end

      it 'is off when the claim no longer holds, without deleting it' do
        create(:slack_workspace, team_id: 'T_SUB', duo_namespace: other_group)

        expect(presenter.rows).to include(a_hash_including(team_id: 'T_SUB', state: :off))
        expect(Integrations::SlackWorkspace::Workspace.for_team('T_SUB')).to be_present
      end
    end

    describe 'installed_in' do
      it 'is empty for a workspace installed in the hierarchy' do
        expect(presenter.rows.pluck(:installed_in)).to all(eq([]))
      end

      it 'is the instance for a workspace installed for the instance' do
        stub_saas_features(gitlab_com_subscriptions: false)
        instance_install('T_SUB')

        expect(described_class.new(group: group, current_user: owner, own_team_id: 'T_SUB').own_row)
          .to include(installed_in: [{ kind: :instance }])
      end
    end

    it 'says whether the Slack app can read mentions of @GitLab' do
      install(create(:project, group: group), 'T_MENTIONS', scopes: [SlackIntegration::SCOPE_APP_MENTIONS_READ])

      expect(presenter.rows.to_h { |row| [row[:team_id], row[:slack_permissions_ok]] })
        .to include('T_MENTIONS' => true, 'T_SUB' => false)
    end

    it 'loads the names once, for the order and the rows' do
      install(create(:project, group: group), 'T_NAMED')

      expect(SlackIntegration).to receive(:team_names).once.and_call_original
      expect(presenter.rows.to_h { |row| [row[:team_id], row[:team_name]] })
        .to include('T_NAMED' => 'Workspace T_NAMED')
    end

    it "answers for the page's own workspace from its own install" do
      own = install(create(:project, group: group), 'T_OWN')
      install(create(:project, group: group), 'T_OWN', scopes: [SlackIntegration::SCOPE_APP_MENTIONS_READ])
        .update!(alias: "0-#{own.alias}")

      rows = described_class.new(group: group, current_user: owner, own_installation: own).rows
      expect(rows.find { |row| row[:team_id] == 'T_OWN' }).to include(slack_permissions_ok: false)

      own.update!(authorized_scope_names: [SlackIntegration::SCOPE_APP_MENTIONS_READ])
      rows = described_class.new(group: group, current_user: owner, own_installation: own.reload).rows
      expect(rows.find { |row| row[:team_id] == 'T_OWN' }).to include(slack_permissions_ok: true)
    end
  end

  describe 'row order' do
    before do
      stub_const("#{described_class}::PAGE_SIZE", 2)
      { 'T_C' => 'beta', 'T_A' => 'Alpha', 'T_B' => 'alpha', 'T_D' => 'Gamma' }.each do |team_id, name|
        create(:slack_integration, :project, project: create(:project, group: group), team_id: team_id,
          team_name: name)
      end
    end

    it 'is by name, then team ID, so pages neither repeat nor skip a row' do
      pages = [0, 2].map { |offset| described_class.new(group: group, current_user: owner, offset: offset).rows }

      expect(pages.flatten.pluck(:team_id)).to eq(%w[T_A T_B T_C T_D])
    end
  end

  describe 'pages' do
    before do
      stub_const("#{described_class}::PAGE_SIZE", 2)
      %w[T1 T2 T3].each { |team_id| install(create(:project, group: group), team_id) }
    end

    it 'shows one page and counts the rest' do
      expect(presenter.rows.pluck(:team_id)).to eq(%w[T1 T2])
      expect(presenter.more_count).to eq(1)
    end

    context 'with an offset ("Show more")' do
      let(:offset) { '2' }

      it 'shows the next page only' do
        expect(presenter.rows.pluck(:team_id)).to eq(%w[T3])
        expect(presenter.more_count).to eq(0)
      end
    end

    it 'never shows more than one page, whatever the offset' do
      expect(described_class.new(group: group, current_user: owner, offset: -5).rows.size).to eq(2)
      expect(described_class.new(group: group, current_user: owner, offset: 10_000).rows).to be_empty
    end

    context 'with one workspace' do
      let(:only_team_id) { 'T3' }

      it 'shows only its row' do
        expect(presenter.rows.pluck(:team_id)).to eq(%w[T3])
      end
    end
  end

  # Each kind of row costs its queries once: a group install (with its copies), a project install, and a
  # claim (the permission checks on the group it names). More rows of those kinds cost nothing more.
  describe 'query count' do
    def rows_for(group)
      described_class.new(group: group, current_user: current_user).rows
    end

    # Three workspaces per round: one on a subgroup (claimed for the group), one on a project, and one claimed
    # by another top-level group of its own that has it installed too.
    def add_workspaces(rounds, prefix)
      rounds.times do |index|
        subgroup_install = install(create(:group, :private, parent: group), "#{prefix}_G#{index}",
          scopes: [SlackIntegration::SCOPE_APP_MENTIONS_READ])
        inherited_copy(create(:project, group: subgroup_install.group), subgroup_install)
        create(:slack_workspace, team_id: subgroup_install.team_id, duo_namespace: group)
        install(create(:project, group: group), "#{prefix}_P#{index}")

        other_group = create(:group, organization: organization)
        install(create(:project, group: group), "#{prefix}_E#{index}")
        install(create(:project, group: other_group), "#{prefix}_E#{index}")
        create(:slack_workspace, team_id: "#{prefix}_E#{index}", duo_namespace: other_group)
      end
    end

    before do
      stub_saas_features(gitlab_com_subscriptions: false)
      add_workspaces(1, 'T_FIRST')
    end

    it 'does not grow with the rows on the group page', :request_store do
      control = ActiveRecord::QueryRecorder.new { expect(rows_for(group).size).to eq(3) }

      add_workspaces(5, 'T_MORE')

      expect { expect(rows_for(group).size).to eq(18) }.not_to exceed_query_limit(control)
    end
  end

  describe '#pointer_notice' do
    let_it_be(:installation) { install(project, 'T_ACME') }

    let(:current_user) { maintainer }
    let(:own_team_id) { 'T_ACME' }
    let(:only_team_id) { 'T_ACME' }

    it 'is off and names the Owners who can turn it on' do
      expect(presenter.own_row).to include(state: :off)
      expect(presenter.pointer_notice).to include(key: :off_ask_owner, group_name: group.full_name,
        link_kind: :owners)
    end

    it 'asks to install the app on the top-level group when it has not installed the workspace' do
      expect(presenter.pointer_notice(top_level_installed: false))
        .to include(key: :off_install_on_top_level, group_name: group.full_name, link_kind: :owners)
    end

    context 'when the viewer cannot see the top-level group' do
      let(:current_user) { create(:user) }

      it 'does not name it' do
        expect(presenter.pointer_notice).to eq(key: :off_ask_owner)
      end
    end

    context 'when GitLab Duo runs in the top-level group' do
      before do
        create(:slack_workspace, team_id: 'T_ACME', duo_namespace: group)
      end

      it 'points to it' do
        expect(presenter.own_row).to include(state: :on_here)
        expect(presenter.pointer_notice).to include(key: :on_here_read_only, group_name: group.full_name)
      end

      context 'for an Owner' do
        let(:current_user) { owner }

        it 'links to the group page where it is decided' do
          expect(presenter.pointer_notice).to include(link_kind: :settings)
        end
      end
    end

    context 'when GitLab Duo runs in a group the viewer can see' do
      let_it_be(:other_group) { create(:group, :public) }

      before do
        install(other_group, 'T_ACME')
        create(:slack_workspace, team_id: 'T_ACME', duo_namespace: other_group)
      end

      it 'names it' do
        expect(presenter.pointer_notice).to include(key: :elsewhere, group_name: other_group.full_name)
      end
    end

    context 'when GitLab Duo runs in a group the viewer cannot see' do
      before do
        other_group = create(:group, :private)
        install(other_group, 'T_ACME')
        create(:slack_workspace, team_id: 'T_ACME', duo_namespace: other_group)
      end

      it 'does not name it' do
        expect(presenter.pointer_notice).to eq(key: :elsewhere_unnamed)
      end
    end

    context 'when the workspace is managed for the instance', :enable_admin_mode do
      let(:current_user) { admin }

      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        instance_install('T_ACME')
      end

      it 'points to the Admin area for an administrator' do
        expect(presenter.own_row).to include(state: :instance_managed)
        expect(presenter.pointer_notice).to include(key: :instance_managed_off, link_kind: :admin)
      end

      context 'when GitLab Duo runs in a group the administrator can see' do
        before do
          create(:slack_workspace, team_id: 'T_ACME', duo_namespace: group)
        end

        it 'names the group' do
          expect(presenter.pointer_notice)
            .to include(key: :instance_managed_on, group_name: group.full_name, link_kind: :admin)
        end
      end

      context 'for a non-administrator' do
        let(:current_user) { maintainer }

        it 'offers no Admin area link' do
          expect(presenter.pointer_notice).to eq(key: :instance_managed_off)
        end

        context 'when GitLab Duo runs in a group the viewer cannot see' do
          before do
            hidden_group = create(:group, :private, organization: organization)
            create(:slack_workspace, team_id: 'T_ACME', duo_namespace: hidden_group)
          end

          it 'says GitLab Duo is on without naming the group', :aggregate_failures do
            expect(presenter.own_row).to include(duo_group: nil, duo_on: true)
            expect(presenter.pointer_notice).to eq(key: :instance_managed_on_unnamed)
          end
        end
      end

      context 'without a current user' do
        let(:current_user) { nil }

        it 'offers no Admin area link' do
          expect(presenter.pointer_notice).to eq(key: :instance_managed_off)
        end
      end
    end
  end

  describe '.installation_for' do
    it 'is the record of the page' do
      installation = install(project, 'T_OWN')

      expect(described_class.installation_for(installation.integration)).to eq(installation)
    end

    it 'follows the install a project without a record of its own inherits' do
      install(group, 'T_GROUP')

      expect(described_class.installation_for(Integrations::GitlabSlackApplication.new(project: project)))
        .to have_attributes(team_id: 'T_GROUP')
    end
  end
end
# rubocop:enable RSpec/FactoryBot/AvoidCreate
