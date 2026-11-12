# frozen_string_literal: true

require 'spec_helper'

RSpec.describe '(Group|Project|Organization).analytics.agentPlatformCreditsSyncedAt',
  :clean_gitlab_redis_shared_state, :freeze_time, :saas_gitlab_com_subscriptions,
  feature_category: :value_stream_management do
  include GraphqlHelpers

  let_it_be(:organization) { create(:organization, :public) }
  let_it_be(:group) { create(:group, organization: organization) }
  let_it_be(:subgroup) { create(:group, parent: group, organization: organization) }
  let_it_be(:group2) { create(:group, organization: organization) }
  let_it_be(:project) { create(:project, group: subgroup) }
  let_it_be(:current_user) { create(:user, reporter_of: [group, group2]) }
  let_it_be(:guest) { create(:user, guest_of: [group, group2]) }

  let(:freshness) { Ai::DuoWorkflows::SessionCredits::SyncFreshness }
  let(:scope_arguments) { '' }

  let(:query) do
    <<~QUERY
      query {
        #{resource_query} {
          analytics {
            agentPlatformCreditsSyncedAt#{scope_arguments.presence && "(#{scope_arguments})"}
          }
        }
      }
    QUERY
  end

  before do
    stub_licensed_features(ai_analytics: true)
  end

  def synced_at
    graphql_data_at(query_type, :analytics, :agent_platform_credits_synced_at)
  end

  def full_paths_argument(*records)
    "[#{records.map { |record| "\"#{record.full_path}\"" }.join(', ')}]"
  end

  shared_examples 'returns the last sync of the root group' do
    it 'returns the root group sync time', :aggregate_failures do
      freshness.record_completion(group.id)

      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(synced_at).to eq(Time.current.iso8601)
    end

    it 'returns null when the root group never completed a sync', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(synced_at).to be_nil
    end
  end

  shared_examples 'returns null without an error' do
    it 'returns null without an error', :aggregate_failures do
      freshness.record_completion(group.id)

      post_graphql(query, current_user: user)

      expect(graphql_errors).to be_nil
      expect(synced_at).to be_nil
    end
  end

  shared_examples 'returns null for inaccessible sources' do
    context 'for a guest' do
      let(:user) { guest }

      it_behaves_like 'returns null without an error'
    end

    context 'when ai_analytics is not licensed' do
      let(:user) { current_user }

      before do
        stub_licensed_features(ai_analytics: false)
      end

      it_behaves_like 'returns null without an error'
    end
  end

  shared_examples 'returns null when dap_impact_v1 is disabled' do
    let(:user) { current_user }

    before do
      stub_feature_flags(dap_impact_v1: false)
    end

    it_behaves_like 'returns null without an error'

    context 'when dap_impact_v1 is enabled for the root group' do
      before do
        stub_feature_flags(dap_impact_v1: group)
      end

      it 'returns the root group sync time', :aggregate_failures do
        freshness.record_completion(group.id)

        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(synced_at).to eq(Time.current.iso8601)
      end
    end
  end

  context 'for group' do
    let(:query_type) { 'group' }
    let(:resource_query) { %(group(fullPath: "#{subgroup.full_path}")) }

    it_behaves_like 'returns the last sync of the root group'
    it_behaves_like 'returns null for inaccessible sources'
    it_behaves_like 'returns null when dap_impact_v1 is disabled'
  end

  context 'for project' do
    let(:query_type) { 'project' }
    let(:resource_query) { %(project(fullPath: "#{project.full_path}")) }

    it_behaves_like 'returns the last sync of the root group'
    it_behaves_like 'returns null for inaccessible sources'
    it_behaves_like 'returns null when dap_impact_v1 is disabled'
  end

  context 'for organization' do
    let(:query_type) { 'organization' }
    let(:resource_query) { %(organization(id: "#{organization.to_global_id}")) }
    let(:scope_arguments) { %(descendantsScope: { groupFullPaths: #{full_paths_argument(group)} }) }

    it_behaves_like 'returns the last sync of the root group'
    it_behaves_like 'returns null for inaccessible sources'
    it_behaves_like 'returns null when dap_impact_v1 is disabled'

    context 'when requesting sources under several root groups' do
      let(:scope_arguments) do
        <<~ARGS
          descendantsScope: {
            groupFullPaths: #{full_paths_argument(group2)}
            projectFullPaths: #{full_paths_argument(project)}
          }
        ARGS
      end

      it 'returns the oldest of their last syncs', :aggregate_failures do
        freshness.record_completion(group.id)
        oldest = Time.current
        travel(3.hours)
        freshness.record_completion(group2.id)

        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(synced_at).to eq(oldest.iso8601)
      end

      it 'returns null when one of them never completed a sync', :aggregate_failures do
        freshness.record_completion(group.id)

        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(synced_at).to be_nil
      end

      context 'when dap_impact_v1 is enabled for only one of the root groups' do
        before do
          stub_feature_flags(dap_impact_v1: group)
        end

        it 'returns null without an error', :aggregate_failures do
          freshness.record_completion(group.id)
          freshness.record_completion(group2.id)

          post_graphql(query, current_user: current_user)

          expect(graphql_errors).to be_nil
          expect(synced_at).to be_nil
        end
      end
    end

    context 'on self-managed' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'returns the instance sync time instead of the root group one', :aggregate_failures do
        freshness.record_completion(nil)
        instance_synced_at = Time.current
        travel(1.hour)
        freshness.record_completion(group.id)

        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(synced_at).to eq(instance_synced_at.iso8601)
      end
    end
  end
end
