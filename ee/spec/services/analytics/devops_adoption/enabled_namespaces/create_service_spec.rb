# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::DevopsAdoption::EnabledNamespaces::CreateService, feature_category: :devops_reports do
  include ExclusiveLeaseHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:display_group) { create(:group) }

  let_it_be(:reporter) do
    create(:user).tap do |u|
      group.add_reporter(u)
      display_group.add_reporter(u)
    end
  end

  let(:current_user) { reporter }

  let(:params) { { namespace: group, display_namespace: display_group } }
  let(:enabled_namespace) { subject.payload[:enabled_namespace] }

  let(:service) { described_class.new(params: params, current_user: current_user) }
  let(:cap_lease_key) { "analytics/devops_adoption/enabled_namespaces:#{display_group.id}" }

  subject(:response) { service.execute }

  before do
    stub_licensed_features(group_level_devops_adoption: true, instance_level_devops_adoption: true)
  end

  it 'persists the enabled_namespace', :aggregate_failures do
    expect(response).to be_success
    expect(enabled_namespace.namespace).to eq(group)
    expect(enabled_namespace.display_namespace).to eq(display_group)
  end

  it 'holds a lease for the display namespace around the count and the insert', :aggregate_failures do
    expect_to_obtain_exclusive_lease(cap_lease_key, timeout: described_class::CAP_LEASE_TTL)

    expect(response).to be_success
    expect(enabled_namespace).to be_persisted
  end

  it 'counts the enabled namespaces on the primary' do
    session = ::Gitlab::Database::LoadBalancing::SessionMap
      .current(Analytics::DevopsAdoption::EnabledNamespace.load_balancer)

    expect(session).to receive(:use_primary).and_call_original

    expect(response).to be_success
  end

  context 'when another request holds the display namespace lease' do
    before do
      stub_exclusive_lease_taken(cap_lease_key, timeout: described_class::CAP_LEASE_TTL)
    end

    it 'returns a lock error without creating the enabled_namespace', :aggregate_failures do
      expect(Analytics::DevopsAdoption::CreateSnapshotWorker).not_to receive(:perform_async)

      expect { response }.not_to change { Analytics::DevopsAdoption::EnabledNamespace.count }

      expect(response).to be_error
      expect(response.reason).to eq(:lock_failed)
      expect(response.message)
        .to eq(_("Another request is updating this display namespace's enabled namespaces. Try again."))
      expect(enabled_namespace).not_to be_persisted
      expect(enabled_namespace.errors.full_messages).to contain_exactly(response.message)
    end
  end

  context 'when the caller already holds the display namespace lease' do
    let(:service) { described_class.new(params: params, current_user: current_user, lock: false) }

    it 'persists the enabled_namespace without taking the lease', :aggregate_failures do
      expect(service).not_to receive(:in_lock)

      expect(response).to be_success
      expect(enabled_namespace).to be_persisted
    end

    context 'when the display namespace has reached the enabled namespaces limit' do
      before do
        stub_const("#{described_class}::MAX_ENABLED_NAMESPACES_PER_DISPLAY_NAMESPACE", 1)
        create(:devops_adoption_enabled_namespace, display_namespace: display_group)
      end

      it 'still returns the limit error', :aggregate_failures do
        expect(service).not_to receive(:in_lock)

        expect { response }.not_to change { Analytics::DevopsAdoption::EnabledNamespace.count }

        expect(response).to be_error
        expect(response.reason).to eq(:limit_reached)
      end
    end
  end

  context 'when the display namespace is one row below the limit' do
    let_it_be(:other_group) { create(:group, reporters: reporter) }

    before do
      stub_const("#{described_class}::MAX_ENABLED_NAMESPACES_PER_DISPLAY_NAMESPACE", 2)
      create(:devops_adoption_enabled_namespace, display_namespace: display_group)
    end

    it 'creates exactly up to the limit across sequential creates', :aggregate_failures do
      expect(response).to be_success

      second = described_class.new(params: { namespace: other_group, display_namespace: display_group },
        current_user: current_user).execute

      expect(second).to be_error
      expect(second.reason).to eq(:limit_reached)
      expect(Analytics::DevopsAdoption::EnabledNamespace.for_display_namespaces(display_group).count).to eq(2)
    end
  end

  it 'schedules for snapshot creation' do
    allow(Analytics::DevopsAdoption::CreateSnapshotWorker).to receive(:perform_async).and_call_original

    response

    expect(Analytics::DevopsAdoption::CreateSnapshotWorker).to have_received(:perform_async).with(Analytics::DevopsAdoption::EnabledNamespace.last.id)
  end

  it 'authorizes for manage_devops_adoption', :aggregate_failures do
    expect(::Ability).to receive(:allowed?).with(current_user, :manage_devops_adoption_namespaces, group).and_return true
    expect(::Ability).to receive(:allowed?).with(current_user, :manage_devops_adoption_namespaces, display_group).and_return true

    response
  end

  context 'without display_namespace_id' do
    before do
      params[:display_namespace] = nil
    end

    it 'authorizes for global manage_devops_adoption', :aggregate_failures do
      expect(::Ability).to receive(:allowed?).with(current_user, :manage_devops_adoption_namespaces, group).and_return true
      expect(::Ability).to receive(:allowed?).with(current_user, :manage_devops_adoption_namespaces, :global).and_return true

      response
    end
  end

  context 'for guests' do
    let(:current_user) { create(:user) }

    it 'returns forbidden error' do
      expect { response }.to raise_error(Analytics::DevopsAdoption::EnabledNamespaces::AuthorizationError)
    end
  end

  context 'when the display namespace has reached the enabled namespaces limit' do
    before do
      stub_const("#{described_class}::MAX_ENABLED_NAMESPACES_PER_DISPLAY_NAMESPACE", 1)
      create(:devops_adoption_enabled_namespace, display_namespace: display_group)
    end

    it 'returns an error without creating the enabled_namespace', :aggregate_failures do
      expect(Analytics::DevopsAdoption::CreateSnapshotWorker).not_to receive(:perform_async)

      expect { response }.not_to change { Analytics::DevopsAdoption::EnabledNamespace.count }

      expect(response).to be_error
      expect(response.reason).to eq(:limit_reached)
      expect(response.message).to eq(format(
        n_(
          'Display namespace has reached the limit of %{limit} enabled namespace',
          'Display namespace has reached the limit of %{limit} enabled namespaces',
          1
        ),
        limit: 1
      ))
      expect(enabled_namespace).not_to be_persisted
      expect(enabled_namespace.errors.full_messages).to contain_exactly(response.message)
    end

    context 'when the existing rows belong to another display namespace' do
      let_it_be(:other_display_group) { create(:group) }

      before do
        Analytics::DevopsAdoption::EnabledNamespace.for_display_namespaces(display_group)
          .update_all(display_namespace_id: other_display_group.id)
      end

      it 'persists the enabled_namespace' do
        expect(response).to be_success
        expect(enabled_namespace).to be_persisted
      end
    end

    context 'without display_namespace', :enable_admin_mode do
      let(:current_user) { create(:admin) }

      before do
        params[:display_namespace] = nil
        create(:devops_adoption_enabled_namespace, display_namespace: nil)
      end

      it 'persists the enabled_namespace' do
        expect(response).to be_success
        expect(enabled_namespace).to be_persisted
      end
    end

    context 'when the devops_adoption_enabled_namespaces_cap feature flag is disabled' do
      before do
        stub_feature_flags(devops_adoption_enabled_namespaces_cap: false)
      end

      it 'persists the enabled_namespace and schedules the snapshot without a lease', :aggregate_failures do
        expect(service).not_to receive(:in_lock)
        expect(Analytics::DevopsAdoption::CreateSnapshotWorker).to receive(:perform_async)

        expect { response }.to change { Analytics::DevopsAdoption::EnabledNamespace.count }.by(1)

        expect(response).to be_success
      end
    end
  end
end
