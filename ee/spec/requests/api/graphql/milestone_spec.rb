# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying a Milestone', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:project) { create(:project, guests: current_user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:milestone) { create(:milestone, project: project, start_date: '2020-01-01', due_date: '2020-01-15') }

  let(:query) do
    graphql_query_for('milestone', { id: milestone.to_global_id.to_s }, fields)
  end

  subject { graphql_data['milestone'] }

  context 'burnupTimeSeries' do
    let(:fields) do
      <<~FIELDS
      report {
        error { code message }
        burnupTimeSeries {
          date
          scopeCount
          scopeWeight
          completedCount
          completedWeight
        }
      }
      FIELDS
    end

    let_it_be(:issue) { create(:issue, project: project) }

    before_all do
      create(:resource_milestone_event, issue: issue, milestone: milestone, action: :add, created_at: '2020-01-05')
    end

    context 'with insufficient license' do
      before do
        stub_licensed_features(milestone_charts: false)
      end

      it 'returns nil' do
        post_graphql(query, current_user: current_user)

        expect(graphql_data_at(:milestone, :report, :error, :code)).to eq 'UNSUPPORTED'
        expect(graphql_data_at(:milestone, :report, :error, :message)).to include('does not support burnup charts')
        expect(graphql_data_at(:milestone, :report, :burnup_time_series)).to be_nil
      end
    end

    context 'when missing dates' do
      let!(:milestone) { create(:milestone, project: project) }

      it 'explains why the report cannot be generated' do
        post_graphql(query, current_user: current_user)

        expect(graphql_data_at(:milestone, :report, :error, :code)).to eq 'MISSING_DATES'
        expect(graphql_data_at(:milestone, :report, :error, :message)).to include('must have a start and due date')
        expect(graphql_data_at(:milestone, :report, :burnup_time_series)).to be_nil
      end
    end

    context 'when there are too many events' do
      before do
        stub_feature_flags(rollup_timebox_chart: false)
        stub_const('TimeboxReportService::EVENT_COUNT_LIMIT', 0)
      end

      it 'explains why the report cannot be generated' do
        post_graphql(query, current_user: current_user)

        expect(graphql_data_at(:milestone, :report, :error, :code)).to eq 'TOO_MANY_EVENTS'
        expect(graphql_data_at(:milestone, :report, :error, :message)).to include('too many')
        expect(graphql_data_at(:milestone, :report, :burnup_time_series)).to be_nil
      end

      context 'when "rollup_timebox_chart" feature flag is enabled' do
        before do
          stub_feature_flags(rollup_timebox_chart: true)
          stub_const('Timebox::EventAggregationService::EVENT_COUNT_LIMIT', 0)
        end

        it 'explains why the report cannot be generated' do
          post_graphql(query, current_user: current_user)

          expect(graphql_data_at(:milestone, :report, :error, :code)).to eq 'TOO_MANY_EVENTS'
          expect(graphql_data_at(:milestone, :report, :error, :message)).to include('too many')
          expect(graphql_data_at(:milestone, :report, :burnup_time_series)).to be_nil
        end
      end
    end

    context 'with correct license' do
      before do
        stub_licensed_features(milestone_charts: true, issue_weights: true)
      end

      it 'returns burnup chart data', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(subject['report']['error']).to be_nil
        expect(subject['report']['burnupTimeSeries']).to include(
          {
            'date' => '2020-01-05',
            'scopeCount' => 1,
            'scopeWeight' => 0,
            'completedCount' => 0,
            'completedWeight' => 0
          }
        )
      end

      context 'when "rollup_timebox_chart" feature flag is disabled' do
        before do
          stub_feature_flags(rollup_timebox_chart: false)
        end

        it 'returns burnup chart data' do
          post_graphql(query, current_user: current_user)

          expect(subject).to eq({
            'report' => {
              'error' => nil,
              'burnupTimeSeries' => [
                {
                  'date' => '2020-01-05',
                  'scopeCount' => 1,
                  'scopeWeight' => 0,
                  'completedCount' => 0,
                  'completedWeight' => 0
                }
              ]
            }
          })
        end
      end
    end
  end

  shared_examples 'milestones queried by timeframe' do
    describe 'query for milestones by timeframe' do
      context 'without start' do
        it 'returns error' do
          post_graphql(milestones_query(parent, "timeframe: { end: \"#{3.days.ago.to_date}\" }"), current_user: current_user)

          expect(graphql_errors).to include(a_hash_including('message' => "Argument 'start' on InputObject 'Timeframe' is required. Expected type Date!"))
        end
      end

      context 'without end date' do
        it 'returns error' do
          post_graphql(milestones_query(parent, "timeframe: { start: \"#{3.days.ago.to_date}\" }"), current_user: current_user)

          expect(graphql_errors).to include(a_hash_including('message' => "Argument 'end' on InputObject 'Timeframe' is required. Expected type Date!"))
        end
      end

      context 'with start and end date' do
        it 'does not have errors' do
          post_graphql(milestones_query(parent, "timeframe: { start: \"#{3.days.ago.to_date}\", end: \"#{3.days.from_now.to_date}\" }"), current_user: current_user)

          expect(graphql_errors).to be_nil
        end
      end
    end
  end

  context 'group milestones' do
    it_behaves_like 'milestones queried by timeframe' do
      let(:parent) { group }
    end
  end

  context 'project milestones' do
    it_behaves_like 'milestones queried by timeframe' do
      let(:parent) { project }
    end
  end

  context 'with releases of two projects and a fine-grained personal access token' do
    let_it_be(:releases_group, freeze: false) { create(:group, :private) }
    let_it_be(:group_reporter) { create(:user, reporter_of: releases_group) }
    let_it_be(:released_project, freeze: false) { create(:project, :repository, :private, group: releases_group) }
    let_it_be(:other_project, freeze: false) { create(:project, :repository, :private, group: releases_group) }
    let_it_be(:group_milestone, freeze: false) { create(:milestone, group: releases_group) }
    let_it_be(:release, freeze: false) { create(:release, project: released_project) }
    let_it_be(:other_release, freeze: false) { create(:release, project: other_project) }

    let(:read_milestone) { ::Authz::PermissionGroups::Assignable.for_permission(:read_milestone).min_by(&:name).name }
    let(:group_permissions) { [read_milestone] }
    let(:release_scopes) { [{ boundary: ::Authz::Boundary.for(released_project), permissions: %w[read_release] }] }
    let(:pat) do
      create(:granular_pat, user: group_reporter, boundary: ::Authz::Boundary.for(releases_group),
        permissions: group_permissions, additional_scopes: release_scopes)
    end

    before do
      stub_licensed_features(group_milestone_project_releases: true)
      group_milestone.releases << [release, other_release]

      post_graphql(
        graphql_query_for(:milestone, { id: group_milestone.to_global_id.to_s }, 'releases { nodes { tagName } }'),
        token: { personal_access_token: pat }
      )
    end

    it 'returns the release of the project the token can read releases of', :aggregate_failures do
      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:milestone, :releases, :nodes, :tag_name)).to contain_exactly(release.tag)
    end

    context 'when the token can read the releases of the group' do
      let(:group_permissions) { [read_milestone, 'read_release'] }
      let(:release_scopes) { [] }

      it 'returns the releases of both projects', :aggregate_failures do
        expect(graphql_errors).to be_nil
        expect(graphql_data_at(:milestone, :releases, :nodes, :tag_name))
          .to contain_exactly(release.tag, other_release.tag)
      end
    end
  end

  def project_milestones_query(project, milestone_query)
    <<~QUERY
      query {
        project(fullPath: "#{project.full_path}") {
          id,
          #{milestone_query}
        }
      }
    QUERY
  end

  def group_milestones_query(group, milestone_query)
    <<~QUERY
      query {
        group(fullPath: "#{group.full_path}") {
          id,
          #{milestone_query}
        }
      }
    QUERY
  end

  def milestones_query(parent, field_queries)
    query = <<~Q
      milestones(#{field_queries}) {
        nodes {
          id
        }
      }
    Q

    if parent.is_a?(Group)
      group_milestones_query(parent, query)
    else
      project_milestones_query(parent, query)
    end
  end
end
