# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Mcp::Handlers::ListTools, feature_category: :mcp_server do
  let(:manager) { instance_double(Mcp::Tools::Manager, list_tools: {}) }
  let(:logger) { instance_double(Gitlab::Mcp::Logger) }
  let_it_be(:current_user) { create(:user) }

  subject(:handler) { described_class.new(manager) }

  before do
    allow(Gitlab::Mcp::Logger).to receive(:build).and_return(logger)
    allow(logger).to receive(:conditional_info)
  end

  describe '#invoke' do
    it 'tracks the list tools event' do
      expect { handler.invoke(current_user) }
        .to trigger_internal_events('list_mcp_tools')
        .with(user: current_user)
        .and increment_usage_metrics(
          'counts.count_total_list_mcp_tools_weekly',
          'counts.count_total_list_mcp_tools_monthly',
          'counts.count_total_list_mcp_tools'
        )
    end

    it 'logs the tools list request' do
      handler.invoke(current_user)

      expect(logger).to have_received(:conditional_info).with(
        current_user,
        message: 'MCP tools list',
        event_name: 'tools_list',
        ai_component: 'mcp_server',
        tool_count: 0
      )
    end

    context 'with a toolset selection' do
      let(:allowed_tools) { nil }
      let(:selection) { { source: 'explicit', names: %w[code_security wikis] } }
      let(:properties) do
        { toolset_source: 'explicit', requested_toolsets: 'code_security,wikis', tools_header_present: 'false' }
      end

      subject(:invoke) do
        handler.invoke(current_user, allowed_tools: allowed_tools, toolset_selection: selection)
      end

      it 'tracks and logs an explicit selection' do
        expect { invoke }
          .to trigger_internal_events('list_mcp_tools')
          .with(user: current_user, additional_properties: properties)

        expect(logger).to have_received(:conditional_info).with(
          current_user, message: 'MCP tools list', event_name: 'tools_list', ai_component: 'mcp_server',
          tool_count: 0, **properties
        )
      end

      context 'with the default source' do
        let(:selection) { { source: 'default', names: [] } }

        it 'omits requested_toolsets' do
          expect { invoke }
            .to trigger_internal_events('list_mcp_tools')
            .with(user: current_user,
              additional_properties: { toolset_source: 'default', tools_header_present: 'false' })
        end
      end

      context 'with the all source' do
        let(:selection) { { source: 'all', names: [] } }

        it 'omits requested_toolsets' do
          expect { invoke }
            .to trigger_internal_events('list_mcp_tools')
            .with(user: current_user, additional_properties: { toolset_source: 'all', tools_header_present: 'false' })
        end
      end

      context 'when tool names are given' do
        let(:allowed_tools) { %w[get_work_item secret_tool] }
        let(:manager) do
          instance_double(Mcp::Tools::Manager, list_tools: {}, resolve_alias: 'resolved_name')
        end

        it 'flags the header but never records tool names' do
          allow(logger).to receive(:warn)

          expect { invoke }
            .to trigger_internal_events('list_mcp_tools')
            .with(user: current_user, additional_properties: properties.merge(tools_header_present: 'true'))

          expect(logger).to have_received(:conditional_info) do |_user, **log|
            expect(log.values.join(',')).not_to include('get_work_item', 'secret_tool', 'resolved_name')
          end
        end
      end
    end

    it 'omits toolset fields when no selection is given' do
      handler.invoke(current_user)

      expect(logger).to have_received(:conditional_info) do |_user, **log|
        expect(log.keys).not_to include(:toolset_source, :requested_toolsets, :tools_header_present)
      end
    end
  end
end
