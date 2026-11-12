# frozen_string_literal: true

require 'spec_helper'

RSpec.describe '(Group|Project|Organization).analytics.duoToolCalls', :click_house, time_travel_to: '2026-01-30',
  feature_category: :product_analytics do
  include GraphqlHelpers
  include ClickHouseHelpers

  let_it_be(:organization) { create(:organization, :public) }
  let_it_be(:group) { create(:group, organization: organization) }
  let_it_be(:group2) { create(:group, organization: organization) }
  let_it_be(:project1) { create(:project, group: group) }
  let_it_be(:project2) { create(:project, group: group2) }
  let_it_be(:current_user) { create(:user, reporter_of: [group, group2]) }
  let_it_be(:guest) { create(:user, guest_of: [group, group2]) }

  let_it_be(:user1) { create(:user) }
  let_it_be(:user2) { create(:user) }

  let(:succeeded) { Ai::UsageEvent.events[:tool_succeeded_duo_chat] }
  let(:failed) { Ai::UsageEvent.events[:tool_failed_duo_chat] }

  # Session 1 reads then writes, session 2 only reads, session 3 runs a command,
  # session 4 calls a tool the registry does not know. Timestamps are spread out
  # because the table dedups rows that share its sort key.
  let(:events_data) do
    rows = [
      tool_call(user: user1, event: succeeded, session_id: 1, tool_name: 'get_issue'),
      tool_call(user: user1, event: succeeded, session_id: 1, tool_name: 'create_issue'),
      tool_call(user: user1, event: succeeded, session_id: 2, tool_name: 'list_issues'),
      tool_call(user: user1, event: failed, session_id: 2, tool_name: 'get_merge_request'),
      tool_call(user: user2, event: failed, session_id: 3, tool_name: 'run_command'),
      tool_call(user: user2, event: succeeded, session_id: 4, tool_name: 'some_mcp_tool'),
      event_row(user: user2, event: Ai::UsageEvent.events[:request_duo_chat_response]),
      tool_call(user: user2, event: succeeded, session_id: 5, tool_name: 'get_issue', project: project2)
    ]

    rows.each_with_index.map { |row, index| row.merge(timestamp: 10.days.ago + index.seconds) }
  end

  let(:minimal_query) do
    <<~QUERY
      query {
        #{resource_query} {
          analytics {
            duoToolCalls#{field_arguments(%(timestampFrom: "#{60.days.ago.iso8601}"))} {
              aggregated {
                nodes { totalCount }
              }
            }
          }
        }
      }
    QUERY
  end

  def event_row(user:, event:, project: project1, extras: {})
    {
      user_id: user.id,
      event: event,
      timestamp: 10.days.ago,
      namespace_path: project.project_namespace.traversal_path(with_organization: false),
      traversal_path: project.project_namespace.traversal_path(with_organization: true),
      extras: extras
    }
  end

  def tool_call(user:, event:, session_id:, tool_name:, project: project1)
    event_row(user: user, event: event, project: project,
      extras: { session_id: session_id, tool_name: tool_name, flow_type: 'chat' })
  end

  def full_paths_argument(*records)
    "[#{records.map { |record| "\"#{record.full_path}\"" }.join(', ')}]"
  end

  def field_arguments(filters = nil)
    args = [scope_arguments, filters].compact_blank.join("\n")

    args.blank? ? '' : "(#{args})"
  end

  before do
    stub_licensed_features(ai_analytics: true)
    allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)

    clickhouse_fixture(:ai_usage_events, events_data)
  end

  shared_examples 'reports inaccessible sources' do
    it 'reports the requested sources as inaccessible for guest' do
      post_graphql(minimal_query, current_user: guest)

      expect(graphql_errors).to match(
        [hash_including('message' => "The following sources are not accessible: #{inaccessible_source.full_path}")]
      )
    end

    it 'reports the requested sources as inaccessible when ai_analytics is not licensed' do
      stub_licensed_features(ai_analytics: false)

      post_graphql(minimal_query, current_user: current_user)

      expect(graphql_errors).to match(
        [hash_including('message' => "The following sources are not accessible: #{inaccessible_source.full_path}")]
      )
    end
  end

  shared_examples 'duoToolCalls query' do
    let(:aggregated_data) { graphql_data.dig(query_type, 'analytics', 'duoToolCalls', 'aggregated') }

    context 'when querying all metrics' do
      let(:query) do
        <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoToolCalls#{field_arguments(%(
                  timestampFrom: "#{60.days.ago.iso8601}"
                  timestampTo: "#{5.days.ago.iso8601}"
                ))} {
                  aggregated {
                    nodes {
                      totalCount
                      usersCount
                      sessionsCount
                      writeSessionsCount
                      readOnlySessionsCount
                      successRate
                    }
                  }
                }
              }
            }
          }
        QUERY
      end

      it 'returns the tool call metrics for the scope', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil

        node = aggregated_data['nodes'].sole
        expect(node).to include(
          'totalCount' => 6, 'usersCount' => 2, 'sessionsCount' => 4,
          'writeSessionsCount' => 2, 'readOnlySessionsCount' => 1
        )
        expect(node['successRate']).to be_within(0.001).of(4.0 / 6)
      end
    end

    context 'when grouping by tool access and filtering by event' do
      let(:query) do
        <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoToolCalls#{field_arguments(%(event: ["tool_succeeded_duo_chat"], timestampFrom: "#{60.days.ago.iso8601}"))} {
                  aggregated(orderBy: [{ identifier: "toolAccess", direction: ASC }]) {
                    nodes {
                      dimensions { toolAccess }
                      totalCount
                    }
                  }
                }
              }
            }
          }
        QUERY
      end

      it 'classifies the succeeded calls by access type', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(aggregated_data['nodes']).to match_array([
          { 'dimensions' => { 'toolAccess' => 'read' }, 'totalCount' => 2 },
          { 'dimensions' => { 'toolAccess' => 'write' }, 'totalCount' => 1 },
          { 'dimensions' => { 'toolAccess' => nil }, 'totalCount' => 1 }
        ])
      end
    end

    context 'when the filter leaves no calls' do
      let(:query) do
        <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoToolCalls#{field_arguments(%(toolName: ["no_such_tool"], timestampFrom: "#{60.days.ago.iso8601}"))} {
                  aggregated {
                    nodes { totalCount successRate }
                  }
                }
              }
            }
          }
        QUERY
      end

      it 'returns a null success rate rather than zero' do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(aggregated_data['nodes']).to match_array([{ 'totalCount' => 0, 'successRate' => nil }])
      end
    end
  end

  context 'for group' do
    let(:query_type) { 'group' }
    let(:resource_query) { %(group(fullPath: "#{group.full_path}")) }
    let(:scope_arguments) { '' }
    let(:inaccessible_source) { group }

    it_behaves_like 'duoToolCalls query'
    it_behaves_like 'reports inaccessible sources'

    context 'when grouping by group' do
      let_it_be(:subgroup) { create(:group, parent: group) }
      let_it_be(:subgroup_project) { create(:project, group: subgroup) }

      let(:events_data) do
        [
          tool_call(user: user1, event: succeeded, session_id: 1, tool_name: 'get_issue'),
          tool_call(user: user2, event: failed, session_id: 2, tool_name: 'get_issue', project: subgroup_project)
        ]
      end

      let(:nodes) { graphql_data.dig(query_type, 'analytics', 'duoToolCalls', 'aggregated', 'nodes') }

      let(:query) do
        <<~QUERY
          query {
            #{resource_query} {
              analytics {
                duoToolCalls#{field_arguments(%(timestampFrom: "#{60.days.ago.iso8601}"))} {
                  aggregated {
                    nodes {
                      dimensions {
                        group(depth: #{subgroup.traversal_ids.size}) { id fullPath }
                      }
                      usersCount
                    }
                  }
                }
              }
            }
          }
        QUERY
      end

      it 'resolves the subgroup and leaves calls from projects at that depth without a group' do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(nodes).to match_array([
          {
            'dimensions' => { 'group' => { 'id' => subgroup.to_global_id.to_s, 'fullPath' => subgroup.full_path } },
            'usersCount' => 1
          },
          { 'dimensions' => { 'group' => nil }, 'usersCount' => 1 }
        ])
      end
    end
  end

  context 'for project' do
    let(:query_type) { 'project' }
    let(:resource_query) { %(project(fullPath: "#{project1.full_path}")) }
    let(:scope_arguments) { '' }
    let(:inaccessible_source) { project1 }

    it_behaves_like 'duoToolCalls query'
    it_behaves_like 'reports inaccessible sources'
  end

  context 'for organization' do
    let(:query_type) { 'organization' }
    let(:resource_query) { %(organization(id: "#{organization.to_global_id}")) }
    let(:scope_arguments) { %(descendantsScope: { groupFullPaths: #{full_paths_argument(group)} }) }
    let(:inaccessible_source) { group }

    it_behaves_like 'duoToolCalls query'
    it_behaves_like 'reports inaccessible sources'
  end
end
