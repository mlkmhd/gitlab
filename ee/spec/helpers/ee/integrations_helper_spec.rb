# frozen_string_literal: true

require 'spec_helper'

# FIXME: feature_category is fixed but this test covers integrations that
# are owned by different groups
RSpec.describe EE::IntegrationsHelper, feature_category: :not_owned do # rubocop:disable RSpec/FeatureCategory -- See above
  let_it_be(:organization) { create(:common_organization) }
  let_it_be_with_refind(:group) { create(:group) }
  let_it_be_with_refind(:project) { create(:project, group: group) }

  describe '#integration_form_data' do
    context 'when integration is at the project level' do
      let(:integration) { build(:jenkins_integration) }

      let(:jira_fields) do
        {
          show_jira_issues_integration: 'false',
          show_jira_vulnerabilities_integration: 'false',
          enable_jira_issues: 'true',
          enable_jira_vulnerabilities: 'false',
          project_key: 'FE',
          project_keys: 'FE,BE',
          vulnerabilities_issuetype: '10001',
          customize_jira_issue_enabled: 'false'
        }
      end

      subject(:form_data) { helper.integration_form_data(integration, project: project) }

      it 'does not include Jira-specific fields' do
        is_expected.not_to include(*jira_fields.keys)
      end

      context 'with a Jira integration' do
        let(:integration) { build(:jira_integration, project: project, issues_enabled: true, project_key: 'FE', project_keys: %w[FE BE], vulnerabilities_enabled: true, vulnerabilities_issuetype: '10001', customize_jira_issue_enabled: false) }

        context 'when there is no license for jira_vulnerabilities_integration' do
          before do
            allow(integration).to receive(:jira_vulnerabilities_integration_available?).and_return(false)
          end

          it 'includes default Jira fields' do
            is_expected.to include(jira_fields)
          end
        end

        context 'when all flags are enabled' do
          before do
            stub_licensed_features(jira_issues_integration: true, jira_vulnerabilities_integration: true)
          end

          it 'includes all Jira fields' do
            is_expected.to include(
              jira_fields.merge(
                show_jira_issues_integration: 'true',
                show_jira_vulnerabilities_integration: 'true',
                enable_jira_vulnerabilities: 'true'
              )
            )
          end
        end
      end

      context 'with Google Artifact Registry integration' do
        let(:integration) { build_stubbed(:google_cloud_platform_artifact_registry_integration, project: project) }

        shared_examples 'active iam integration' do
          it 'is editable' do
            is_expected.to include(editable: 'true')
          end

          it 'does not include workload_identity_federation_path field' do
            is_expected.not_to include(:workload_identity_federation_path)
          end

          it 'includes wlif fields' do
            is_expected.to include(
              workload_identity_federation_project_number: project.google_cloud_platform_workload_identity_federation_integration.workload_identity_federation_project_number,
              workload_identity_pool_id: project.google_cloud_platform_workload_identity_federation_integration.workload_identity_pool_id
            )
          end
        end

        shared_examples 'inactive iam integration' do
          it 'is not-editable' do
            is_expected.to include(editable: 'false')
          end

          it 'includes workload_identity_federation_path field' do
            is_expected.to include(
              workload_identity_federation_path: edit_project_settings_integration_path(project, :google_cloud_platform_workload_identity_federation)
            )
          end

          it 'does not includes wlif fields' do
            is_expected.not_to include(
              :workload_identity_federation_project_number,
              :workload_identity_pool_id
            )
          end
        end

        it 'includes Google Artifact Registry fields' do
          is_expected.to include(
            artifact_registry_path: project_google_cloud_artifact_registry_index_path(project),
            operating: 'true'
          )
        end

        context 'when Google Cloud IAM integration does not exist' do
          it_behaves_like 'inactive iam integration'
        end

        context 'with active Google Cloud IAM integration' do
          before do
            create(:google_cloud_platform_workload_identity_federation_integration, project: project)
          end

          it_behaves_like 'active iam integration'
        end

        context 'with inactive Google Cloud IAM integration' do
          before do
            create(:google_cloud_platform_workload_identity_federation_integration, project: project, active: false)
          end

          it_behaves_like 'inactive iam integration'
        end
      end

      context 'with Google Cloud IAM integration' do
        let(:integration) do
          build_stubbed(:google_cloud_platform_workload_identity_federation_integration, project: project)
        end

        it 'include wlif_issuer field' do
          is_expected.to include(
            wlif_issuer: ::Integrations::GoogleCloudPlatform::WorkloadIdentityFederation.wlif_issuer_url(project),
            jwt_claims: ::Integrations::GoogleCloudPlatform::WorkloadIdentityFederation.jwt_claim_mapping_script_value
          )
        end
      end
    end

    context 'when integration is at the group level' do
      let(:integration) { build(:google_cloud_platform_workload_identity_federation_integration, group: group) }

      subject(:form_data) { helper.integration_form_data(integration, group: group) }

      context 'with Google Cloud IAM integration' do
        it 'include wlif_issuer field' do
          is_expected.to include(
            wlif_issuer: ::Integrations::GoogleCloudPlatform::WorkloadIdentityFederation.wlif_issuer_url(group),
            jwt_claims: ::Integrations::GoogleCloudPlatform::WorkloadIdentityFederation.jwt_claim_mapping_script_value
          )
        end
      end
    end

    context 'when integration is at the instance level' do
      let(:integration) { build_stubbed(:amazon_q_integration) }

      subject(:form_data) { helper.integration_form_data(build(:amazon_q_integration)) }

      context 'with Amazon Q integration' do
        before do
          stub_current_organization(organization)
          ::Ai::Setting.for_organization(organization).update!(
            amazon_q_ready: true,
            amazon_q_role_arn: 'role-arn'
          )
        end

        it 'returns the data related to amazon q' do
          identity_provider_params = {
            instance_uid: 'instance_uid',
            aws_provider_url: "https://auth.token.gitlab.com/cc/oidc/instance_uid",
            aws_audience: "gitlab-cc-instance_uid"
          }

          expect_next_instance_of(::Ai::AmazonQ::IdentityProviderPayloadFactory) do |instance|
            expect(instance).to receive(:execute).and_return({ ok: identity_provider_params })
          end

          is_expected.to include({
            amazon_q: {
              submit_url: admin_ai_amazon_q_settings_path,
              disconnect_url: disconnect_admin_ai_amazon_q_settings_path,
              ready: "true",
              role_arn: "role-arn",
              availability: :default_on,
              auto_review_enabled: "false"
            }.merge(identity_provider_params)
          })

          expect(flash[:alert]).to be_nil
        end

        it 'adds an error to flash if identity provider factory fails' do
          expect_next_instance_of(::Ai::AmazonQ::IdentityProviderPayloadFactory) do |instance|
            expect(instance).to receive(:execute).and_return({ err: { message: 'failure' } })
          end

          amazon_q_data(integration)

          expect(flash[:alert]).to eq('Something went wrong retrieving the identity provider payload. failure')
        end
      end
    end

    context 'with the GitLab for Slack app' do
      let_it_be(:owner) { create(:user, owner_of: group) }
      let_it_be(:installation) { create(:slack_integration, :group, group: group, team_id: 'T_FORM') }

      let(:integration) { installation.integration }
      let(:slack_duo) { Gitlab::Json.parse(form_data[:slack_duo]) }

      subject(:form_data) { helper.integration_form_data(integration, group: group) }

      before do
        allow(helper).to receive(:current_user).and_return(owner)
        stub_application_setting(instance_level_ai_beta_features_enabled: true)
      end

      it 'includes the GitLab Duo section of the top-level group page' do
        expect(slack_duo).to include('scope' => 'group', 'own_team_id' => 'T_FORM')
      end

      context 'on a project page' do
        let(:integration) { Integrations::GitlabSlackApplication.new(project: project) }

        subject(:form_data) { helper.integration_form_data(integration, project: project) }

        it 'includes the pointer to where GitLab Duo is decided' do
          expect(slack_duo).to include('scope' => 'pointer')
        end

        context 'with the inherited settings form of the top-level group' do
          subject(:form_data) { helper.integration_form_data(installation.integration, project: project) }

          it { is_expected.not_to have_key(:slack_duo) }
        end
      end

      context 'when slack_duo_group is disabled for the top-level group' do
        before do
          stub_feature_flags(slack_duo_group: false)
        end

        it { is_expected.not_to have_key(:slack_duo) }
      end

      context 'when experiment and beta Duo features are turned off' do
        before do
          stub_application_setting(instance_level_ai_beta_features_enabled: false)
        end

        it { is_expected.not_to have_key(:slack_duo) }
      end

      context 'on the instance-wide install' do
        let(:integration) { create(:slack_integration, :instance).integration }

        subject(:form_data) { helper.integration_form_data(integration) }

        it { is_expected.not_to have_key(:slack_duo) }
      end
    end

    context 'with the GitLab for Slack app in the Admin area' do
      let_it_be(:admin) { create(:admin) }
      let_it_be(:instance_installation) do
        create(:slack_integration, :instance, organization: organization, team_id: 'T_ADMIN')
      end

      let(:integration) { instance_installation.integration }
      let(:current_user) { admin }

      subject(:form_data) { helper.integration_form_data(integration) }

      before do
        allow(helper).to receive(:current_user).and_return(current_user)
        stub_application_setting(instance_level_ai_beta_features_enabled: true)
      end

      context 'in admin mode', :enable_admin_mode do
        it 'includes the GitLab Duo section of the instance workspace' do
          expect(Gitlab::Json.parse(form_data[:slack_duo_admin]))
            .to include('scope' => 'admin', 'state' => 'off', 'team_id' => 'T_ADMIN')
          expect(form_data).not_to have_key(:slack_duo)
        end

        context 'without an install for the instance' do
          let(:integration) { Integrations::GitlabSlackApplication.new(instance: true, organization: create(:organization)) }

          it 'includes the section, not connected' do
            expect(Gitlab::Json.parse(form_data[:slack_duo_admin])).to include('state' => 'not_connected')
          end
        end

        context 'when slack_duo_group is disabled for the instance' do
          before do
            stub_feature_flags(slack_duo_group: false)
          end

          it { is_expected.not_to have_key(:slack_duo_admin) }
        end

        context 'when experiment and beta Duo features are turned off' do
          before do
            stub_application_setting(instance_level_ai_beta_features_enabled: false)
          end

          it { is_expected.not_to have_key(:slack_duo_admin) }
        end

        context 'on a group page' do
          let(:integration) { create(:slack_integration, :group, group: group).integration }

          subject(:form_data) { helper.integration_form_data(integration, group: group) }

          it { is_expected.not_to have_key(:slack_duo_admin) }
        end

        # Group and project pages render the instance integration as their inherited settings form.
        context 'with the inherited settings form of a group page' do
          subject(:form_data) { helper.integration_form_data(integration, group: group) }

          it { is_expected.not_to have_key(:slack_duo_admin) }
        end

        context 'with the inherited settings form of a project page' do
          subject(:form_data) { helper.integration_form_data(integration, project: project) }

          it { is_expected.not_to have_key(:slack_duo_admin) }
        end

        # The endpoint acts on the administrator's current organization, not the page's.
        context "on an organization's integration page" do
          subject(:form_data) { helper.integration_form_data(integration, organization: organization) }

          it { is_expected.not_to have_key(:slack_duo_admin) }
        end
      end

      context 'without admin mode' do
        it { is_expected.not_to have_key(:slack_duo_admin) }
      end

      context 'without a current user' do
        let(:current_user) { nil }

        it { is_expected.not_to have_key(:slack_duo_admin) }
      end
    end
  end

  describe '#integrations_allow_list_data' do
    let_it_be(:allow_all_integrations) { false }
    let_it_be(:allowed_integrations) { ['jira'] }
    let_it_be(:application_setting) do
      build_stubbed(:application_setting, integrations: {
        allow_all_integrations: allow_all_integrations, allowed_integrations: allowed_integrations
      })
    end

    subject(:allow_list_data) { helper.integrations_allow_list_data }

    before do
      helper.instance_variable_set(:@application_setting, application_setting)
    end

    it 'includes integrations list as JSON' do
      integrations = Gitlab::Json.parse(allow_list_data[:integrations])

      expect(integrations).to be_an_instance_of(Array)
      expect(integrations).to include(
        { 'title' => 'Slack notifications', 'name' => 'slack' }
      )
    end

    it 'includes setting values' do
      is_expected.to include(
        allow_all_integrations: 'false',
        allowed_integrations: '["jira"]'
      )
    end
  end

  describe '#jira_issues_show_data' do
    subject { helper.jira_issues_show_data }

    before do
      allow(helper).to receive(:params).and_return({ id: 'FE-1' })
      assign(:project, project)
    end

    it 'includes Jira issues show data' do
      is_expected.to include(
        issues_show_path: "/#{project.full_path}/-/integrations/jira/issues/FE-1.json",
        issues_list_path: "/#{project.full_path}/-/integrations/jira/issues"
      )
    end
  end

  describe '#integration_form_data with a GitLab for Slack app integration' do
    let_it_be_with_reload(:integration) do
      create(:gitlab_slack_application_integration, :all_features_supported, project: project)
    end

    subject(:should_upgrade_slack_for_duo) { helper.integration_form_data(integration)[:should_upgrade_slack_for_duo] }

    before do
      allow(helper).to receive_messages(
        current_user: build_stubbed(:user),
        slack_auth_project_settings_slack_url: 'http://redirect'
      )
    end

    context 'when experiment and beta Duo features are turned on' do
      before do
        stub_application_setting(instance_level_ai_beta_features_enabled: true)
      end

      it { is_expected.to eq('true') }

      context 'when the installation has the Duo scopes' do
        before do
          integration.slack_integration.update!(
            authorized_scope_names: SlackIntegration.scopes_for(duo_enabled: true)
          )
        end

        it { is_expected.to eq('false') }
      end
    end

    context 'when experiment and beta Duo features are turned off' do
      before do
        stub_application_setting(instance_level_ai_beta_features_enabled: false)
      end

      it { is_expected.to eq('false') }
    end
  end

  describe '#add_to_slack_link' do
    let(:user) { build_stubbed(:user) }
    let(:query) { Rack::Utils.parse_query(URI.parse(helper.add_to_slack_link(project, 'A12345')).query) }

    before do
      allow(helper).to receive_messages(
        form_authenticity_token: 'a token',
        current_user: user,
        slack_auth_project_settings_slack_url: 'http://redirect'
      )
    end

    context 'when experiment and beta Duo features are turned on' do
      before do
        stub_application_setting(instance_level_ai_beta_features_enabled: true)
      end

      it 'requests the DUO_SCOPES and AGENT_APP_SCOPES' do
        expect(query).to include(
          'scope' => (SlackIntegration::DUO_SCOPES + SlackIntegration::AGENT_APP_SCOPES).join(',')
        )
      end

      context 'when the slack_duo_agent_app release flag is disabled' do
        before do
          stub_feature_flags(slack_duo_agent_app: false)
        end

        it 'requests only the DUO_SCOPES' do
          expect(query).to include('scope' => SlackIntegration::DUO_SCOPES.join(','))
        end
      end
    end

    context 'when experiment and beta Duo features are turned off' do
      before do
        stub_application_setting(instance_level_ai_beta_features_enabled: false)
      end

      it 'requests the base SCOPES' do
        expect(query).to include('scope' => SlackIntegration::SCOPES.join(','))
      end
    end
  end

  describe '#external_issue_breadcrumb_title' do
    let(:expected_title) { 'my-ref' }

    subject { helper.external_issue_breadcrumb_title(issue_reference) }

    context 'with a valid issue_reference' do
      let(:issue_reference) { 'my-ref' }

      it 'returns the correct HTML' do
        is_expected.to eq(expected_title)
      end
    end

    context 'when issue_reference contains HTML' do
      let(:issue_reference) { "<script>alert('XSS')</script>my-ref" }

      it 'strips all tags' do
        is_expected.to eq(expected_title)
      end
    end
  end

  describe '#slack_integration_destroy_confirm_message' do
    let_it_be(:owner) { create(:user, owner_of: group) }
    let_it_be(:installation) do
      create(:slack_integration, :group, group: group, team_id: 'T_ACME', team_name: 'Acme Eng')
    end

    let(:ce_text) do
      '<p>Are you sure you want to unlink this Slack Workspace from this integration? All projects inheriting ' \
        'these settings will also be unlinked. Groups and projects using custom settings will not be affected.</p>'
    end

    subject(:message) { helper.slack_integration_destroy_confirm_message(installation.integration) }

    before do
      allow(helper).to receive(:current_user).and_return(owner)
    end

    it 'is the CE text when GitLab Duo does not run for the workspace' do
      expect(message).to eq(ce_text)
    end

    context 'when GitLab Duo runs for the workspace in the group' do
      before do
        create(:slack_workspace, team_id: 'T_ACME', duo_namespace: group)
      end

      it 'says that removing the last install turns it off' do
        expect(message).to eq("#{ce_text}<p>If this is the last install of Acme Eng in #{group.full_name}, " \
          'GitLab Duo in Slack turns off for it.</p>')
      end

      it 'does not name the group to someone who cannot see it' do
        allow(helper).to receive(:can?).and_call_original
        allow(helper).to receive(:can?).with(owner, :read_group, group).and_return(false)

        expect(message).to eq("#{ce_text}<p>If this is the last install of Acme Eng in its top-level group, " \
          'GitLab Duo in Slack turns off for it.</p>')
      end

      it 'escapes the workspace name' do
        project_install = create(:slack_integration, :project, project: project, team_id: 'T_ACME',
          team_name: '<b>Acme</b>')

        message = helper.slack_integration_destroy_confirm_message(project_install.integration)

        expect(message).to include('&lt;b&gt;Acme&lt;/b&gt;')
        expect(message).not_to include('<b>')
      end

      it 'says so while another install stays in the group, without checking the other installs' do
        create(:slack_integration, :project, project: project, team_id: 'T_ACME')

        expect(message).to include('If this is the last install of Acme Eng')
      end

      it 'is the CE text for an install outside the group' do
        other_install = create(:slack_integration, :group, group: create(:group), team_id: 'T_ACME')

        expect(helper.slack_integration_destroy_confirm_message(other_install.integration)).to eq(ce_text)
      end

      it 'is the CE text when the administrator decides' do
        stub_saas_features(gitlab_com_subscriptions: false)
        create(:slack_integration, :instance, organization: group.organization, team_id: 'T_ACME')

        expect(message).to eq(ce_text)
      end

      context 'when slack_duo_group is disabled' do
        before do
          stub_feature_flags(slack_duo_group: false)
        end

        it 'is the CE text' do
          expect(message).to eq(ce_text)
        end
      end
    end

    context 'when the install is instance-level' do
      let_it_be(:instance_installation) do
        create(:slack_integration, :instance, organization: group.organization, team_id: 'T_INST',
          team_name: 'Instance Co')
      end

      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        create(:slack_workspace, team_id: 'T_INST', duo_namespace: group)
      end

      it 'says GitLab Duo turns off unless the group has its own install, naming the group' do
        expect(helper.slack_integration_destroy_confirm_message(instance_installation.integration))
          .to include("If #{group.full_name} has no install of Instance Co of its own, GitLab Duo in Slack turns off")
      end

      it 'does not name the group to someone who cannot see it' do
        private_group = create(:group, :private, organization: group.organization)
        Integrations::SlackWorkspace::Workspace.for_team('T_INST').destroy!
        create(:slack_workspace, team_id: 'T_INST', duo_namespace: private_group)
        allow(helper).to receive(:current_user).and_return(create(:user))

        message = helper.slack_integration_destroy_confirm_message(instance_installation.integration)

        expect(message).to include('If its top-level group has no install of Instance Co of its own')
        expect(message).not_to include(private_group.full_name)
      end
    end
  end

  describe '#slack_duo_admin_feature_available?' do
    using RSpec::Parameterized::TableSyntax

    where(:duo_group, :beta_features, :available) do
      true  | true  | true
      false | true  | false
      true  | false | false
    end

    with_them do
      before do
        stub_feature_flags(slack_duo_group: duo_group)
        stub_application_setting(instance_level_ai_beta_features_enabled: beta_features)
      end

      it { expect(helper.slack_duo_admin_feature_available?).to be(available) }
    end
  end

  describe '#slack_duo_group_feature_available?' do
    using RSpec::Parameterized::TableSyntax

    let_it_be_with_refind(:subgroup) { create(:group, parent: group) }

    context 'on GitLab Self-Managed' do
      where(:duo_group, :beta_features, :available) do
        true  | true  | true
        false | true  | false
        true  | false | false
      end

      with_them do
        before do
          stub_feature_flags(slack_duo_group: duo_group)
          stub_application_setting(instance_level_ai_beta_features_enabled: beta_features)
        end

        it { expect(helper.slack_duo_group_feature_available?(group)).to be(available) }
      end
    end

    context 'on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'follows the experiment features of the top-level group' do
        group.namespace_settings.update_column(:experiment_features_enabled, true)

        expect(helper.slack_duo_group_feature_available?(group)).to be(true)
        expect(helper.slack_duo_group_feature_available?(subgroup)).to be(true)
        expect(helper.slack_duo_group_feature_available?(project)).to be(true)
      end

      it 'is false with them off' do
        group.namespace_settings.update_column(:experiment_features_enabled, false)

        expect(helper.slack_duo_group_feature_available?(group)).to be(false)
        expect(helper.slack_duo_group_feature_available?(project)).to be(false)
      end
    end
  end

  describe '#slack_duo_data' do
    let_it_be(:owner) { create(:user, owner_of: group) }
    # Reloaded: the page reads its own install's scopes from this object.
    let_it_be_with_reload(:installation) do
      create(:slack_integration, :group, group: group, team_id: 'T_ACME', team_name: 'Acme Eng')
    end

    let(:current_user) { owner }

    before do
      allow(helper).to receive(:current_user).and_return(current_user)
    end

    context 'on the top-level group page' do
      subject(:data) { helper.slack_duo_data(installation.integration) }

      it 'shows its own workspace first, with no requirements while GitLab Duo is off' do
        expect(data).to include(scope: :group, state: :workspaces, own_team_id: 'T_ACME', requirements: [],
          more_count: 0, update_path: helper.duo_group_group_settings_slack_path(group))
        expect(data[:workspaces].first).to include(team_id: 'T_ACME', state: :off, can_manage: true)
        expect(data).not_to have_key(:updated_workspace)
      end

      it 'shows the requirements when GitLab Duo runs here for a workspace beyond the first page' do
        stub_const('Integrations::SlackWorkspace::DuoWorkspacesPresenter::PAGE_SIZE', 1)
        create(:slack_integration, :project, project: project, team_id: 'T_ZZZ')
        create(:slack_workspace, team_id: 'T_ZZZ', duo_namespace: group)

        expect(data[:workspaces].pluck(:team_id)).to eq(%w[T_ACME])
        expect(data[:requirements].pluck(:id)).to include(:duo_features)
      end

      it 'adds the row of a changed workspace' do
        expect(helper.slack_duo_data(installation.integration, updated_team_id: 'T_ACME')[:updated_workspace])
          .to include(team_id: 'T_ACME', state: :off)
      end

      it 'links the reinstall only for its own workspace' do
        create(:slack_integration, :project, project: project, team_id: 'T_BELOW')

        rows = data[:workspaces].index_by { |row| row[:team_id] }

        expect(rows['T_ACME'][:reinstall_path])
          .to eq(helper.edit_group_settings_integration_path(group, :gitlab_slack_application))
        expect(rows['T_BELOW'][:reinstall_path]).to be_nil
      end

      it 'has no reinstall link once the app can read mentions' do
        installation.update!(authorized_scope_names: [SlackIntegration::SCOPE_APP_MENTIONS_READ])

        expect(data[:workspaces].first).not_to have_key(:reinstall_path)
      end

      context 'for someone who cannot change GitLab Duo in Slack' do
        let(:current_user) { create(:user, maintainer_of: group) }

        it 'offers no change' do
          expect(data).to include(update_path: nil, requirements: [], seats_required: false)
        end
      end

      context 'without a current user' do
        let(:current_user) { nil }

        it 'offers no Admin area paths' do
          expect(data).to include(admin_integration_path: nil, instance_settings_path: nil)
        end
      end

      context 'for an administrator, with a workspace managed for the instance' do
        let(:current_user) { create(:admin) }

        before do
          stub_saas_features(gitlab_com_subscriptions: false)
          allow(current_user).to receive(:can_admin_all_resources?).and_return(true)
          create(:slack_integration, :instance, organization: group.organization, team_id: 'T_ACME',
            team_name: 'Acme Eng')
        end

        it 'links the reinstall and the GitLab Duo settings to the Admin area' do
          admin_path = helper.edit_admin_application_settings_integration_path(:gitlab_slack_application)

          expect(data[:workspaces].first).to include(state: :instance_managed, reinstall_path: admin_path)
          expect(data).to include(admin_integration_path: admin_path,
            instance_settings_path: helper.admin_gitlab_duo_configuration_index_path)
        end
      end
    end

    context 'on a later page ("Show more")' do
      before do
        stub_const('Integrations::SlackWorkspace::DuoWorkspacesPresenter::PAGE_SIZE', 1)
        create(:slack_integration, :project, project: project, team_id: 'T_BELOW')
      end

      it 'has only its rows and how many are left' do
        data = helper.slack_duo_data(installation.integration, offset: 1)

        expect(data.keys).to contain_exactly(:workspaces, :more_count)
        expect(data).to include(more_count: 0)
        expect(data[:workspaces].pluck(:team_id)).to eq(%w[T_BELOW])
      end

      it 'has no rows past the end, without saying the group is not connected' do
        expect(helper.slack_duo_data(installation.integration, offset: 5)).to eq(workspaces: [], more_count: 0)
      end
    end

    context 'on a top-level group with no workspaces' do
      it 'is not connected' do
        bare_group = create(:group)

        expect(helper.slack_duo_data(Integrations::GitlabSlackApplication.new(group: bare_group)))
          .to include(scope: :group, state: :not_connected, workspaces: [], own_team_id: nil)
      end
    end

    context 'on a subgroup page' do
      let_it_be(:subgroup) { create(:group, parent: group) }

      let(:integration) { Integrations::GitlabSlackApplication.new(group: subgroup) }

      before do
        stub_application_setting(slack_app_enabled: true)
      end

      it 'points to where GitLab Duo is decided' do
        expect(helper.slack_duo_data(integration)).to include(
          scope: :pointer, state: :off, team_name: 'Acme Eng',
          notice: a_hash_including(key: :off_ask_owner, group_name: group.full_name, link_kind: :settings)
        )
      end

      context 'with a workspace of its own that the top-level group has not installed' do
        let(:integration) do
          create(:slack_integration, :group, group: subgroup, team_id: 'T_SUB', team_name: 'Sub Eng').integration
        end

        it 'asks to install the app on the top-level group' do
          expect(helper.slack_duo_data(integration)).to include(
            scope: :pointer, state: :off, team_name: 'Sub Eng',
            notice: a_hash_including(key: :off_install_on_top_level, group_name: group.full_name)
          )
        end
      end

      context 'when GitLab Duo runs in the top-level group' do
        before do
          create(:slack_workspace, team_id: 'T_ACME', duo_namespace: group)
        end

        it "does not look up the top-level group's install" do
          expect(Integrations::GitlabSlackApplication).not_to receive(:for_group)

          expect(helper.slack_duo_data(integration)).to include(scope: :pointer, state: :on_here)
        end
      end
    end

    context 'on a project page' do
      it 'says GitLab Duo cannot run in a personal namespace' do
        personal = create(:slack_integration, :project, project: create(:project, namespace: create(:user_namespace)))

        expect(helper.slack_duo_data(personal.integration))
          .to include(scope: :pointer, state: :personal_namespace, notice: { key: :personal_namespace })
      end

      it 'says the page is not connected without an install' do
        unconnected = Integrations::GitlabSlackApplication.new(project: create(:project, group: create(:group)))

        expect(helper.slack_duo_data(unconnected))
          .to include(scope: :pointer, state: :not_connected, notice: { key: :not_connected })
      end
    end
  end

  describe '#slack_duo_admin_data', :enable_admin_mode do
    let_it_be(:admin) { create(:admin) }
    let_it_be(:duo_group) { create(:group, organization: organization) }

    subject(:data) { helper.slack_duo_admin_data(organization) }

    before do
      allow(helper).to receive(:current_user).and_return(admin)
    end

    it 'is not connected without an instance install' do
      expect(data).to include(scope: :admin, state: :not_connected,
        update_path: helper.duo_group_admin_application_settings_slack_path)
    end

    context 'with a workspace installed for the instance' do
      let_it_be_with_reload(:installation) do
        create(:slack_integration, :instance, organization: organization, team_id: 'T_ACME', team_name: 'Acme')
      end

      it 'is off, links the reinstall while the app cannot read mentions, and shows no requirements' do
        expect(data).to include(scope: :admin, state: :off, team_id: 'T_ACME', team_name: 'Acme', duo_group: nil,
          requirements: [], slack_permissions_ok: false, group_settings_path: nil,
          reinstall_path: helper.edit_admin_application_settings_integration_path(:gitlab_slack_application),
          instance_settings_path: helper.admin_gitlab_duo_configuration_index_path)
      end

      it 'has no reinstall link once the app can read mentions' do
        installation.update!(authorized_scope_names: [SlackIntegration::SCOPE_APP_MENTIONS_READ])

        expect(data).to include(slack_permissions_ok: true, reinstall_path: nil)
      end

      it 'names the Duo group and shows its requirements' do
        create(:slack_workspace, team_id: 'T_ACME', duo_namespace: duo_group)

        expect(data).to include(state: :on, duo_group: include(id: duo_group.id, name: duo_group.full_name),
          group_settings_path: duo_group.duo_settings_path)
        expect(data[:requirements].pluck(:id)).to include(:duo_features)
      end

      it 'shows a claim that no longer holds as off' do
        create(:slack_workspace, team_id: 'T_ACME', duo_namespace: create(:group, organization: create(:organization)))

        expect(data).to include(state: :off, duo_group: nil, requirements: [])
      end
    end
  end

  describe '#zentao_issue_breadcrumb_link' do
    subject { helper.zentao_issue_breadcrumb_link(issue_json) }

    context 'with valid issue JSON' do
      let(:issue_json) { { id: "my-ref", web_url: "https://example.com" } }

      it 'returns the correct HTML' do
        is_expected.to eq('<img width="15" height="15" class="gl-mr-2 lazy" data-src="/assets/logos/zentao-91a4a40cfe1a1640cb4fcf645db75e0ce23fbb9984f649c0675e616d6ff8c632.svg" src="data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==" /><a target="_blank" rel="noopener noreferrer" class="gl-flex gl-items-center gl-whitespace-nowrap" href="https://example.com">my-ref</a>')
      end
    end

    context 'when issue_reference contains XSS' do
      let(:issue_json) { { id: "<script>alert('XSS')</script>my-ref", web_url: "javascript:alert('XSS')" } }

      it 'strips all tags and sanitizes' do
        is_expected.to eq('<img width="15" height="15" class="gl-mr-2 lazy" data-src="/assets/logos/zentao-91a4a40cfe1a1640cb4fcf645db75e0ce23fbb9984f649c0675e616d6ff8c632.svg" src="data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==" /><a target="_blank" rel="noopener noreferrer" class="gl-flex gl-items-center gl-whitespace-nowrap">my-ref</a>')
      end
    end
  end
end
