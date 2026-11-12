# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Analytics::DevopsAdoption::EnabledNamespaces::BulkEnable, feature_category: :devops_reports do
  include GraphqlHelpers
  include ExclusiveLeaseHelpers

  let_it_be(:display_group) { create(:group, name: 'dddd') }
  let_it_be(:group) { create(:group, name: 'aaaa', parent: display_group) }
  let_it_be(:group2) { create(:group, name: 'bbbb', parent: display_group) }
  let_it_be(:group3) { create(:group, name: 'cccc', parent: display_group) }

  let_it_be(:reporter) do
    create(:user).tap do |u|
      display_group.add_reporter(u)
      group.add_reporter(u)
      group2.add_reporter(u)
      group3.add_reporter(u)
    end
  end

  let_it_be(:existing_enabled_namespace) { create :devops_adoption_enabled_namespace, namespace: group3, display_namespace: display_group }

  let(:current_user) { reporter }

  let(:variables) { { namespace_ids: [group.to_gid.to_s, group2.to_gid.to_s, group3.to_gid.to_s], display_namespace_id: display_group.to_gid.to_s } }

  let(:mutation) do
    graphql_mutation(:bulk_enable_devops_adoption_namespaces, variables) do
      <<-QL.strip_heredoc
        clientMutationId
        errors
        enabledNamespaces {
          id
          namespace {
            name
          }
          displayNamespace {
            name
          }
        }
      QL
    end
  end

  def mutation_response
    graphql_mutation_response(:bulk_enable_devops_adoption_namespaces)
  end

  before do
    stub_licensed_features(group_level_devops_adoption: true)
  end

  context 'when the user cannot manage enabled_namespaces at least for one namespace' do
    let(:current_user) { create(:user, reporter_of: group) }

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when the feature is not available' do
    before do
      stub_licensed_features(group_level_devops_adoption: false)
    end

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when one namespace is in another isolated organization', :enable_admin_mode do
    let_it_be(:isolated_group) { create(:group, name: 'iiii', organization: create(:organization, :isolated)) }

    let(:current_user) { create(:admin) }
    let(:variables) do
      { namespace_ids: [group.to_gid.to_s, isolated_group.to_gid.to_s], display_namespace_id: display_group.to_gid.to_s }
    end

    it 'returns the validation error and enables the other namespaces', :aggregate_failures do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(mutation_response['errors'])
        .to contain_exactly('Namespace must be in the same organization as the display namespace')
      expect(mutation_response['enabledNamespaces'].map { |s| s['namespace']['name'] }).to contain_exactly('aaaa')
      expect(::Analytics::DevopsAdoption::EnabledNamespace.for_namespaces(isolated_group)).to be_empty
    end
  end

  it 'creates the enabled_namespace for each passed namespace or returns existing enabled_namespace' do
    post_graphql_mutation(mutation, current_user: current_user)

    expect(mutation_response['errors']).to be_empty

    enabled_namespaces = mutation_response['enabledNamespaces']
    expect(enabled_namespaces.map { |s| s['namespace']['name'] }).to match_array(%w[aaaa bbbb cccc])
    expect(enabled_namespaces.map { |s| s['displayNamespace']['name'] }).to match_array(%w[dddd dddd dddd])
    expect(enabled_namespaces.map { |s| s['id'] }).to include(existing_enabled_namespace.to_gid.to_s)
    expect(::Analytics::DevopsAdoption::EnabledNamespace.joins(:namespace)
                                                        .where(namespaces: { name: %w[aaaa bbbb cccc] }).count).to eq(3)
  end

  context 'when another request holds the display namespace lease' do
    before do
      stub_exclusive_lease_taken(
        "analytics/devops_adoption/enabled_namespaces:#{display_group.id}",
        timeout: ::Analytics::DevopsAdoption::EnabledNamespaces::BulkFindOrCreateService::CAP_LEASE_TTL
      )
    end

    it 'returns the lock error and no enabled namespaces', :aggregate_failures do
      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .not_to change { ::Analytics::DevopsAdoption::EnabledNamespace.count }

      expect(mutation_response['errors'])
        .to contain_exactly(_("Another request is updating this display namespace's enabled namespaces. Try again."))
      expect(mutation_response['enabledNamespaces']).to be_empty
    end
  end

  context 'when the display namespace reaches the enabled namespaces limit part way through' do
    before do
      stub_const(
        'Analytics::DevopsAdoption::EnabledNamespaces::CreateService::MAX_ENABLED_NAMESPACES_PER_DISPLAY_NAMESPACE', 2
      )
    end

    it 'returns the rows enabled before and after the limit with the error once', :aggregate_failures do
      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .to change { ::Analytics::DevopsAdoption::EnabledNamespace.count }.by(1)

      expect(mutation_response['errors'])
        .to contain_exactly(format(
          n_(
            'Display namespace has reached the limit of %{limit} enabled namespace',
            'Display namespace has reached the limit of %{limit} enabled namespaces',
            2
          ),
          limit: 2
        ))
      expect(mutation_response['enabledNamespaces'].map { |s| s['namespace']['name'] }).to match_array(%w[aaaa cccc])
    end
  end
end
