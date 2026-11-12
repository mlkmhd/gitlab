# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::DevopsAdoption::EnabledNamespaces::BulkFindOrCreateService, feature_category: :value_stream_management do
  include ExclusiveLeaseHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:group2) { create(:group) }
  let_it_be(:display_group) { create(:group) }

  let_it_be(:reporter) do
    create(:user).tap do |u|
      group.add_reporter(u)
      group2.add_reporter(u)
      display_group.add_reporter(u)
    end
  end

  let_it_be(:enabled_namespace) { create :devops_adoption_enabled_namespace, namespace: group, display_namespace: display_group }

  let(:current_user) { reporter }
  let(:params) { { namespaces: [group, group2], display_namespace: display_group } }
  let(:service) { described_class.new(params: params, current_user: current_user) }
  let(:cap_lease_key) { "analytics/devops_adoption/enabled_namespaces:#{display_group.id}" }

  subject(:response) { service.execute }

  before do
    stub_licensed_features(group_level_devops_adoption: true, instance_level_devops_adoption: true)
  end

  it 'authorizes for manage_devops_adoption', :aggregate_failures do
    expect(::Ability).to receive(:allowed?)
                           .with(current_user, :manage_devops_adoption_namespaces, group)
                           .at_least(1)
                           .and_return(true)
    expect(::Ability).to receive(:allowed?)
                           .with(current_user, :manage_devops_adoption_namespaces, group2)
                           .at_least(1)
                           .and_return(true)
    expect(::Ability).to receive(:allowed?)
                           .with(current_user, :manage_devops_adoption_namespaces, display_group)
                           .at_least(2)
                           .and_return(true)

    response
  end

  context 'when the user cannot manage enabled_namespaces at least for one namespace' do
    let(:current_user) { create(:user, reporter_of: group) }

    it 'returns forbidden error' do
      expect { response }.to raise_error(Analytics::DevopsAdoption::EnabledNamespaces::AuthorizationError)
    end
  end

  it 'returns existing enabled_namespaces for namespaces and creates new one if none exists' do
    expect { response }.to change { ::Analytics::DevopsAdoption::EnabledNamespace.count }.by(1)
    expect(response.payload.fetch(:enabled_namespaces)).to include(enabled_namespace)
  end

  it 'takes one lease for the display namespace around the whole request', :aggregate_failures do
    allow(Gitlab::ExclusiveLease).to receive(:new).and_call_original
    expect(Gitlab::ExclusiveLease).to receive(:new)
      .with(cap_lease_key, timeout: described_class::CAP_LEASE_TTL).once.and_call_original
    expect(Gitlab::ExclusiveLease).not_to receive(:new)
      .with(cap_lease_key, timeout: Analytics::DevopsAdoption::EnabledNamespaces::CreateService::CAP_LEASE_TTL)

    expect { response }.to change { ::Analytics::DevopsAdoption::EnabledNamespace.count }.by(1)
    expect(response).to be_success
  end

  context 'when another request holds the display namespace lease' do
    before do
      stub_exclusive_lease_taken(cap_lease_key, timeout: described_class::CAP_LEASE_TTL)
    end

    it 'returns a lock error without creating or returning any enabled_namespace', :aggregate_failures do
      expect { response }.not_to change { ::Analytics::DevopsAdoption::EnabledNamespace.count }

      expect(response).to be_error
      expect(response.reason).to eq(:lock_failed)
      expect(response.message)
        .to eq(_("Another request is updating this display namespace's enabled namespaces. Try again."))
      expect(response.payload.fetch(:enabled_namespaces)).to be_empty
    end
  end

  context 'when a namespace is listed more than once' do
    let(:params) { { namespaces: [group2, group2, group], display_namespace: display_group } }

    it 'creates it once and returns it once', :aggregate_failures do
      expect { response }.to change { ::Analytics::DevopsAdoption::EnabledNamespace.count }.by(1)

      expect(response.payload.fetch(:enabled_namespaces).map(&:namespace)).to eq([group2, group])
    end
  end

  context 'when the display namespace reaches the enabled namespaces limit part way through' do
    let_it_be(:group3) { create(:group, reporters: reporter) }
    let_it_be(:group4) { create(:group, reporters: reporter) }
    let_it_be(:enabled_namespace4) do
      create :devops_adoption_enabled_namespace, namespace: group4, display_namespace: display_group
    end

    let(:params) { { namespaces: [group, group2, group3, group4], display_namespace: display_group } }

    before do
      stub_const(
        'Analytics::DevopsAdoption::EnabledNamespaces::CreateService::MAX_ENABLED_NAMESPACES_PER_DISPLAY_NAMESPACE', 3
      )
    end

    it 'keeps the rows created before the limit, reports it once and still returns existing rows',
      :aggregate_failures do
      expect { response }.to change { ::Analytics::DevopsAdoption::EnabledNamespace.count }.by(1)

      expect(response).to be_error
      expect(response.reason).to eq(:limit_reached)
      expect(response.message).to eq(format(
        n_(
          'Display namespace has reached the limit of %{limit} enabled namespace',
          'Display namespace has reached the limit of %{limit} enabled namespaces',
          3
        ),
        limit: 3
      ))

      enabled_namespaces = response.payload.fetch(:enabled_namespaces)
      expect(enabled_namespaces.map(&:namespace)).to eq([group, group2, group3, group4])
      expect(enabled_namespaces.values_at(0, 1, 3)).to all(be_persisted)
      expect(enabled_namespaces.values_at(0, 3)).to eq([enabled_namespace, enabled_namespace4])
      expect(enabled_namespaces[2]).not_to be_persisted
      expect(enabled_namespaces[2].errors.full_messages).to contain_exactly(response.message)
    end

    context 'when the devops_adoption_enabled_namespaces_cap feature flag is disabled' do
      before do
        stub_feature_flags(devops_adoption_enabled_namespaces_cap: false)
      end

      it 'creates the remaining enabled_namespaces without a lease', :aggregate_failures do
        expect(service).not_to receive(:in_lock)

        expect { response }.to change { ::Analytics::DevopsAdoption::EnabledNamespace.count }.by(2)

        expect(response).to be_success
        expect(response.payload.fetch(:enabled_namespaces)).to all(be_persisted)
      end
    end
  end
end
