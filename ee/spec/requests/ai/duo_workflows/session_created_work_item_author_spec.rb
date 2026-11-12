# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Author of a work item created in an agent session', :request_store, feature_category: :agent_observability do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:human) { create(:user, developer_of: project) }
  let_it_be(:service_account) do
    create(:user, :service_account, composite_identity_enforced: true, developer_of: project,
      provisioned_by_group: group)
  end

  let_it_be(:workflow) do
    create(:duo_workflows_workflow, project: project, user: human, service_account: service_account)
  end

  let_it_be(:flow_token) do
    create(:oauth_access_token,
      organization: project.organization,
      application: create(:doorkeeper_application),
      resource_owner: service_account,
      expires_in: 1.hour,
      scopes: ::Gitlab::Auth::AI_WORKFLOW_SCOPES + ["user:#{human.id}"])
  end

  let(:headers) { { 'X-Gitlab-Duo-Workflow-Id' => workflow.id.to_s } }
  let(:created_links) { Ai::DuoWorkflows::WorkflowWorkItem.where(work_item_id: created_work_item.id) }

  before_all do
    add_on_purchase = create(:gitlab_subscription_add_on_purchase, :duo_enterprise, :active, namespace: nil)
    create(:gitlab_subscription_user_add_on_assignment, user: human, add_on_purchase: add_on_purchase)
    project.project_setting.update!(duo_features_enabled: true)
  end

  before do
    stub_feature_flags(agent_presence_consolidation: true)
    stub_licensed_features(ai_workflows: true, ai_features: true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
  end

  shared_examples 'stores the session author' do |default_author:|
    let(:default_author_user) { public_send(default_author) }

    it 'stores the human as the author and links the session once', :aggregate_failures do
      create_work_item

      expect(created_work_item.author).to eq(human)
      expect(created_links.map { |link| [link.workflow, link.link_type] }).to eq([[workflow, 'created']])
    end

    context 'without the workflow header' do
      let(:headers) { {} }

      it "stores the #{default_author.to_s.tr('_', ' ')} as the author and records no link", :aggregate_failures do
        create_work_item

        expect(created_work_item.author).to eq(default_author_user)
        expect(created_links).to be_empty
      end
    end

    context "with the header of another human's session" do
      let_it_be(:other_workflow) do
        create(:duo_workflows_workflow, project: project, user: create(:user, developer_of: project),
          service_account: service_account)
      end

      let(:headers) { { 'X-Gitlab-Duo-Workflow-Id' => other_workflow.id.to_s } }

      it "stores the #{default_author.to_s.tr('_', ' ')} as the author and records no link", :aggregate_failures do
        create_work_item

        expect(created_work_item.author).to eq(default_author_user)
        expect(created_links).to be_empty
      end
    end

    context 'when agent_presence_consolidation is disabled' do
      before do
        stub_feature_flags(agent_presence_consolidation: false)
      end

      it "stores the #{default_author.to_s.tr('_', ' ')} as the author and still links the session",
        :aggregate_failures do
        create_work_item

        expect(created_work_item.author).to eq(default_author_user)
        expect(created_links.map(&:workflow)).to eq([workflow])
      end
    end
  end

  context 'when created through the REST API' do
    let(:created_work_item) { WorkItem.find(json_response['id']) }

    def create_work_item
      post api("/projects/#{project.id}/issues", oauth_access_token: flow_token),
        params: { title: 'Created in a session' }, headers: headers

      expect(response).to have_gitlab_http_status(:created)
    end

    it_behaves_like 'stores the session author', default_author: :service_account
  end

  context 'when created through the GraphQL API' do
    let(:mutation) do
      graphql_mutation(:workItemCreate,
        {
          'projectPath' => project.full_path,
          'title' => 'Created in a session',
          'workItemTypeId' => build(:work_item_system_defined_type, :task).to_gid.to_s
        },
        'workItem { id } errors')
    end

    let(:created_work_item) do
      GlobalID::Locator.locate(graphql_mutation_response(:work_item_create).dig('workItem', 'id'))
    end

    def create_work_item
      post_graphql(mutation.query, variables: mutation.variables, token: { oauth_access_token: flow_token },
        headers: headers)

      expect(graphql_mutation_response(:work_item_create)['errors']).to be_empty
    end

    it_behaves_like 'stores the session author', default_author: :human
  end
end
