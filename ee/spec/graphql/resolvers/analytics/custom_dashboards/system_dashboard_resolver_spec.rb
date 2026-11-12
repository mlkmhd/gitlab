# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Analytics::CustomDashboards::SystemDashboardResolver, feature_category: :custom_dashboards_foundation do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }

  let(:slug) { 'dap_impact' }
  let(:args) { { slug: slug } }
  let(:current_user) { user }

  subject(:resolved_dashboard) do
    sync(resolve(described_class, args: args, ctx: { current_user: current_user }))
  end

  describe '#resolve' do
    context 'when the user is authenticated' do
      it 'returns the matching system dashboard' do
        expect(resolved_dashboard).to have_attributes(slug: slug)
      end

      context 'when dap_impact_v1 is disabled' do
        before do
          stub_feature_flags(dap_impact_v1: false)
        end

        it 'creates a resource-not-available graphql error' do
          expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ResourceNotAvailable) do
            resolved_dashboard
          end
        end
      end

      context 'with the merge request analytics dashboard' do
        let(:slug) { 'merge_request_analytics' }

        before do
          allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
        end

        it 'returns the dashboard' do
          expect(resolved_dashboard).to have_attributes(slug: slug)
        end

        context 'when gi_migration_merge_request_analytics is disabled' do
          before do
            stub_feature_flags(gi_migration_merge_request_analytics: false)
          end

          it 'creates a resource-not-available graphql error' do
            expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ResourceNotAvailable) do
              resolved_dashboard
            end
          end
        end

        context 'when ClickHouse is not enabled for analytics' do
          before do
            allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
          end

          it 'creates a resource-not-available graphql error' do
            expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ResourceNotAvailable) do
              resolved_dashboard
            end
          end
        end
      end

      context 'with the Value Streams Dashboard' do
        let(:slug) { 'value_streams_dashboard' }

        before do
          stub_licensed_features(group_level_analytics_dashboard: true)
        end

        it 'returns the dashboard' do
          expect(resolved_dashboard).to have_attributes(slug: slug)
        end

        context 'when gi_migration_value_streams_dashboard is disabled' do
          before do
            stub_feature_flags(gi_migration_value_streams_dashboard: false)
          end

          it 'creates a resource-not-available graphql error' do
            expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ResourceNotAvailable) do
              resolved_dashboard
            end
          end
        end

        context 'when the licence does not include group level analytics dashboards' do
          before do
            stub_licensed_features(group_level_analytics_dashboard: false)
          end

          it 'creates a resource-not-available graphql error' do
            expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ResourceNotAvailable) do
              resolved_dashboard
            end
          end
        end
      end

      context 'when no dashboard matches the slug' do
        let(:slug) { 'non_existing_slug' }

        it 'returns nil' do
          expect(resolved_dashboard).to be_nil
        end
      end
    end

    context 'when the user is unauthenticated' do
      let(:current_user) { nil }

      it 'creates a resource-not-available graphql error' do
        expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ResourceNotAvailable) do
          resolved_dashboard
        end
      end

      context 'when no dashboard matches the slug' do
        let(:slug) { 'non_existing_slug' }

        it 'returns nil without checking authorization' do
          expect(resolved_dashboard).to be_nil
        end
      end
    end
  end
end
