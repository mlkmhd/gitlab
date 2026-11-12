# frozen_string_literal: true

module QA
  RSpec.describe 'Ai-powered', feature_category: :dap_triggers do
    describe 'Duo Developer flow started by a mention in CI' do
      let(:workload_tag) { 'gitlab--duo' }
      let(:flow_reference) { 'developer/v1' }
      let(:admin_api_client) { Runtime::User::Store.admin_api_client }
      let(:owner) { create(:user, :with_personal_access_token, api_client: admin_api_client) }
      let(:api_client) { owner.api_client }

      # Rails HTML-escapes the comment before it goes into the prompt, so a comment cannot carry
      # agentic-mock directives. The mock then returns this default text (ai_gateway/models/agentic_mock.py
      # in the AI Gateway repository), with no tool calls, so the flow finishes and posts it as the reply.
      let(:mock_default_response) { 'mock response (no response tag specified)' }

      let(:group) do
        QA::Resource::Sandbox.fabricate_via_api! do |sandbox|
          sandbox.api_client = admin_api_client
          sandbox.path = "dap-mention-group-#{SecureRandom.hex(4)}"
        end
      end

      let(:project) do
        QA::Resource::Project.fabricate_via_api! do |project|
          project.api_client = api_client
          project.group = group
          project.name = "dap-mention-project-#{SecureRandom.hex(4)}"
          project.initialize_with_readme = true
          project.description = 'Duo Developer mention trigger CI smoke test'
        end
      end

      let(:runner) do
        # Duo Agent Platform jobs may only run on instance-wide or top-level group runners
        create(:group_runner,
          api_client: api_client,
          group: group,
          name: "dap-mention-runner-#{SecureRandom.hex(4)}",
          tags: [workload_tag],
          executor: :docker)
      end

      let(:issue) do
        create(:issue,
          api_client: api_client,
          project: project,
          title: 'Ask Duo Developer for a status update')
      end

      let(:service_account) do
        EE::Flow::FoundationalFlow.service_account_username(project, flow_reference: flow_reference,
          api_client: api_client)
      end

      # Calling the lets in `after` would create a resource just to remove it, so `before` records
      # what it created and `after` removes only that.
      let(:created_resources) { [] }

      before do
        # Admin creates the top-level group, then grants the non-admin user Owner on it so the
        # remaining Duo Agent Platform setup runs as that Owner (api_client). Admin also assigns
        # the Owner a Duo seat, required for the create_duo_workflow entitlement gate.
        created_resources << group
        group.add_member(owner, Resource::Members::AccessLevel::OWNER)
        EE::Flow::FoundationalFlow.assign_duo_seat!(owner, api_client: admin_api_client)

        # Enabling developer/v1 also provides its flow trigger for the mention and assign events.
        EE::Flow::FoundationalFlow.enable_on_group!(group, flow_reference: flow_reference, api_client: api_client)
        created_resources << project
        EE::Flow::FoundationalFlow.enable_remote_flows_on_project!(project, api_client: api_client)

        EE::Flow::FoundationalFlow.wait_for_flow_consumer!(group, project, flow_reference: flow_reference,
          api_client: api_client)

        created_resources << runner
        runner.wait_until_online
      end

      after do
        created_resources.reverse_each(&:remove_via_api!)
      end

      context 'on Self-managed', :orchestrated, :duo_agent_platform, :requires_admin do
        it 'runs the flow from an issue mention and replies in the thread' do
          expect(service_account).to be_present, "Expected the '#{flow_reference}' flow to have a service account"

          mention = issue.add_comment(body: "@#{service_account} please reply with a short status update")

          workflow = nil
          begin
            Support::Waiter.wait_until(
              message: 'Wait for the mention to start the Duo Developer flow',
              max_duration: 300,
              sleep_interval: 5
            ) { workflow = EE::Resource::Ai::DuoWorkflow.find_latest_in_project(project, api_client: api_client) }
          rescue Support::Repeater::WaitExceededError
            log_service_account_notes
            raise
          end

          # A flow created through the REST API is also HUMAN, so the flow trigger is what proves
          # that the mention started it.
          aggregate_failures do
            expect(workflow.workflow_definition).to eq(flow_reference)
            expect(workflow.trigger_source).to eq('HUMAN')
            expect(workflow.flow_trigger_id).to be_present, 'Expected the flow to be started by a flow trigger'
          end

          # Wait for the workload pipeline (source: duo_workflow) to be created, then to succeed.
          pipeline = nil
          Support::Waiter.wait_until(
            message: 'Wait for duo_workflow pipeline to be created',
            max_duration: 120,
            sleep_interval: 5
          ) { pipeline = workflow.workload_pipeline }

          begin
            Flow::Pipeline.wait_for_pipeline_to_have_status_by_id(
              project: project,
              pipeline_id: pipeline[:id],
              status: 'success',
              wait: 600
            )
          rescue Support::Repeater::WaitExceededError
            workflow.log_workload_job_traces
            raise
          end

          # With duo_developer_continuable_sessions on, the flow rests after a turn instead of
          # finishing, so this wait needs a change when that flag rolls out.
          terminal_statuses = %w[finished failed stopped]
          workflow_status = nil
          Support::Waiter.wait_until(
            message: 'Wait for workflow to reach a terminal status',
            max_duration: 120,
            sleep_interval: 5
          ) { terminal_statuses.include?(workflow_status = workflow.current_status) }

          log_service_account_notes unless workflow_status == 'finished'
          expect(workflow_status).to eq('finished'),
            "Expected the mention flow to finish, but its status was '#{workflow_status}'"

          begin
            Support::Waiter.wait_until(
              message: "Wait for #{service_account} to reply in the mention thread",
              max_duration: 180,
              sleep_interval: 5
            ) do
              mention_thread_notes(mention).any? do |note|
                !note[:system] && note.dig(:author, :username) == service_account &&
                  note[:body].include?(mock_default_response)
              end
            end
          rescue Support::Repeater::WaitExceededError
            log_service_account_notes
            raise
          end
        end
      end

      def mention_thread_notes(mention)
        thread = issue.discussions.find { |discussion| discussion[:notes].any? { |note| note[:id] == mention[:id] } }
        thread ? thread[:notes] : []
      end

      # The service account posts an error note instead of the reply when the flow fails, so log
      # its notes to show why the reply did not arrive.
      def log_service_account_notes
        issue.comments.select { |note| note.dig(:author, :username) == service_account }.each do |note|
          Runtime::Logger.info("Note #{note[:id]} by #{service_account}: #{note[:body]}")
        end
      rescue StandardError => e
        Runtime::Logger.warn("Could not log the notes of #{service_account}: #{e.class}: #{e.message}")
      end
    end
  end
end
