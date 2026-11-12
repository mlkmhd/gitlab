# frozen_string_literal: true

module Ai
  module FlowTriggers
    # The loop in which Duo Developer fixes a merge request after each request for changes of its reviewer.
    # A custom flow that fixes code gets the event without these checks.
    module FixLoop
      def self.applies_to?(flow_trigger)
        flow_trigger.developer_flow?
      end

      def self.developer_reference
        ::Ai::Catalog::FoundationalFlow.developer_v1.foundational_flow_reference
      end

      # The first active Duo Developer flow trigger that a request for changes on the merge request runs, with the
      # filter checks of the trigger worker. A note before the first fix run uses its service account.
      def self.flow_trigger_for(merge_request)
        flow_triggers = ::Ai::FlowTrigger
          .applicable_to_project(merge_request.target_project, triggered_on: :merge_request).ordered_by_id
        filter_data = ::Ai::FlowTriggers::MergeRequestFilterData.for(merge_request)
          .merge('action' => 'requested_changes')

        flow_triggers.find do |flow_trigger|
          applies_to?(flow_trigger) && runs_on_requested_changes?(flow_trigger, filter_data)
        end
      end

      def self.runs_on_requested_changes?(flow_trigger, filter_data)
        ::Ai::FlowTriggers::FilterEvaluator.new(
          flow_trigger: flow_trigger, hook_scope: :merge_request, data: filter_data
        ).allowed?
      end
      private_class_method :runs_on_requested_changes?

      # RunService adds the account of an inherited flow trigger to the project when it runs. A note can come before
      # any run, for example for an invalid configuration, and the account needs the membership to post it.
      def self.add_inherited_service_account(flow_trigger, project)
        # A fix loop trigger always has a catalog consumer, because FixLoop reads the flow from it.
        return unless flow_trigger.ai_catalog_item_consumer.inheritance? && flow_trigger.service_account

        response = ::Ai::Catalog::AddServiceAccountToProjectService
          .new(flow_trigger.service_account, project, current_user: nil).execute
        return unless response.error?

        ::Gitlab::AppJsonLogger.warn(class: name,
          message: 'Fix loop could not add the service account to the project.',
          flow_trigger_id: flow_trigger.id, project_id: project.id, error_message: response.message)
      end
    end
  end
end
